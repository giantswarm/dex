package server

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/stretchr/testify/require"
	xoauth2 "golang.org/x/oauth2"

	"github.com/dexidp/dex/server/internal"
	"github.com/dexidp/dex/server/oauth2"
	"github.com/dexidp/dex/server/tokens"
	"github.com/dexidp/dex/storage"
)

// jwtGroups returns the groups claim of a signed token without verifying it.
func jwtGroups(t *testing.T, token string) []string {
	t.Helper()
	parts := strings.Split(token, ".")
	require.Len(t, parts, 3)
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	require.NoError(t, err)
	var claims struct {
		Groups []string `json:"groups"`
	}
	require.NoError(t, json.Unmarshal(payload, &claims))
	return claims.Groups
}

// TestGroupsPrefixCodeAndRefresh logs in with the auth code flow and refreshes,
// with OIDCGroupsPrefix on. Every token carries the mock connector's group with
// the connector ID in front, once.
func TestGroupsPrefixCodeAndRefresh(t *testing.T) {
	ctx := t.Context()
	state := "state"

	httpServer, s := newTestServer(t, func(c *Config) {
		c.OIDCGroupsPrefix = true
	})
	defer httpServer.Close()

	p, err := oidc.NewProvider(ctx, httpServer.URL)
	require.NoError(t, err)

	var config *xoauth2.Config
	var token *xoauth2.Token
	client := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/callback" {
			http.Redirect(w, r, config.AuthCodeURL(state), http.StatusSeeOther)
			return
		}
		q := r.URL.Query()
		if errType := q.Get("error"); errType != "" {
			t.Errorf("got error from server %s: %s", errType, q.Get("error_description"))
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		tok, err := config.Exchange(ctx, q.Get("code"))
		if err != nil {
			t.Errorf("failed to exchange code for token: %v", err)
			return
		}
		token = tok
		w.WriteHeader(http.StatusOK)
	}))
	defer client.Close()

	redirectURL := client.URL + "/callback"
	require.NoError(t, s.storage.CreateClient(ctx, storage.Client{
		ID:           "testclient",
		Secret:       "testclientsecret",
		RedirectURIs: []string{redirectURL},
	}))
	config = &xoauth2.Config{
		ClientID:     "testclient",
		ClientSecret: "testclientsecret",
		Endpoint:     p.Endpoint(),
		Scopes:       []string{oidc.ScopeOpenID, "groups", "offline_access"},
		RedirectURL:  redirectURL,
	}

	resp, err := http.Get(client.URL + "/login")
	require.NoError(t, err)
	resp.Body.Close()
	require.NotNil(t, token, "login did not return a token")

	want := []string{"mock:authors"}
	require.Equal(t, want, jwtGroups(t, token.AccessToken), "access token after login")
	require.Equal(t, want, jwtGroups(t, token.Extra("id_token").(string)), "ID token after login")

	expired := &xoauth2.Token{RefreshToken: token.RefreshToken, Expiry: time.Now().Add(-time.Hour)}
	token, err = config.TokenSource(ctx, expired).Token()
	require.NoError(t, err)
	require.Equal(t, want, jwtGroups(t, token.AccessToken), "access token after refresh")
	require.Equal(t, want, jwtGroups(t, token.Extra("id_token").(string)), "ID token after refresh")

	// The stored refresh token keeps the groups without the prefix, so the next
	// refresh does not prefix them twice.
	var rt internal.RefreshToken
	require.NoError(t, internal.Unmarshal(token.RefreshToken, &rt))
	stored, err := s.storage.GetRefresh(ctx, rt.RefreshId)
	require.NoError(t, err)
	require.Equal(t, []string{"authors"}, stored.Claims.Groups)
}

// TestGroupsPrefixTokenExchange checks that token exchange keeps the groups
// without the connector prefix when OIDCGroupsPrefix is on.
func TestGroupsPrefixTokenExchange(t *testing.T) {
	ctx := t.Context()
	httpServer, s := newTestServer(t, func(c *Config) {
		c.OIDCGroupsPrefix = true
		c.Storage.CreateClient(ctx, storage.Client{
			ID:     "client_1",
			Secret: "secret_1",
		})
	})
	defer httpServer.Close()

	vals := make(url.Values)
	vals.Set("grant_type", oauth2.GrantTypeTokenExchange)
	vals.Set("connector_id", "mock")
	vals.Set("scope", "openid groups")
	vals.Set("requested_token_type", oauth2.TokenTypeID)
	vals.Set("subject_token_type", oauth2.TokenTypeID)
	vals.Set("subject_token", "foobar")
	vals.Set("client_id", "client_1")
	vals.Set("client_secret", "secret_1")

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, httpServer.URL+"/token", strings.NewReader(vals.Encode()))
	req.Header.Set("content-type", "application/x-www-form-urlencoded")
	s.ServeHTTP(rr, req)
	require.Equal(t, http.StatusOK, rr.Code, rr.Body.String())

	var res tokens.Response
	require.NoError(t, json.NewDecoder(rr.Result().Body).Decode(&res))
	require.Equal(t, []string{"authors"}, jwtGroups(t, res.AccessToken))
}
