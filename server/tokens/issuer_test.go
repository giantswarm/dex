package tokens

import (
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/dexidp/dex/server/internal"
	"github.com/dexidp/dex/server/signer"
	"github.com/dexidp/dex/storage"
	"github.com/dexidp/dex/storage/memory"
)

func newTestIssuer(t *testing.T) (*Issuer, storage.Storage) {
	t.Helper()
	logger := slog.New(slog.DiscardHandler)
	store := memory.New(logger)

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	sig, err := signer.NewMockSigner(key)
	require.NoError(t, err)

	issuerURL, err := url.Parse("https://issuer.example.com")
	require.NoError(t, err)

	return NewIssuer(store, sig, *issuerURL, time.Hour, time.Now, logger), store
}

func testAuthorization() Authorization {
	return Authorization{
		Client:        storage.Client{ID: "client-1"},
		Claims:        storage.Claims{UserID: "u1", Username: "alice", Email: "alice@example.com"},
		Scopes:        []string{"openid", "email", "offline_access"},
		ConnectorID:   "mock",
		Nonce:         "n",
		ConnectorData: []byte(`{"conn":"data"}`),
	}
}

func TestIssuerIssue(t *testing.T) {
	ctx := t.Context()
	iss, store := newTestIssuer(t)
	auth := testAuthorization()

	// With refresh requested: access + id + refresh, and the refresh token is persisted.
	ts, err := iss.Issue(ctx, auth, "", true)
	require.NoError(t, err)
	require.NotEmpty(t, ts.AccessToken)
	require.NotEmpty(t, ts.IDToken)
	require.NotEmpty(t, ts.RefreshToken)

	var rt internal.RefreshToken
	require.NoError(t, internal.Unmarshal(ts.RefreshToken, &rt))
	stored, err := store.GetRefresh(ctx, rt.RefreshId)
	require.NoError(t, err)
	require.Equal(t, "client-1", stored.ClientID)
	require.Equal(t, "mock", stored.ConnectorID)
	require.Equal(t, auth.ConnectorData, stored.ConnectorData)

	sess, err := store.GetOfflineSessions(ctx, "u1", "mock")
	require.NoError(t, err)
	require.Contains(t, sess.Refresh, "client-1")

	// Without refresh: access + id only.
	ts2, err := iss.Issue(ctx, auth, "", false)
	require.NoError(t, err)
	require.NotEmpty(t, ts2.AccessToken)
	require.NotEmpty(t, ts2.IDToken)
	require.Empty(t, ts2.RefreshToken)
}

// tokenGroups returns the groups claim of a signed token.
func tokenGroups(t *testing.T, token string) []string {
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

func TestIssuerGroupsPrefix(t *testing.T) {
	tests := []struct {
		name         string
		groupsPrefix bool
		connectorID  string
		skip         bool
		want         []string
	}{
		{name: "prefix off", connectorID: "mock", want: []string{"admins", "devs"}},
		{name: "prefix on", groupsPrefix: true, connectorID: "mock", want: []string{"mock:admins", "mock:devs"}},
		{name: "skipped by the authorization", groupsPrefix: true, connectorID: "mock", skip: true, want: []string{"admins", "devs"}},
		{name: "no connector", groupsPrefix: true, connectorID: "", want: []string{"admins", "devs"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ctx := t.Context()
			iss, store := newTestIssuer(t)
			iss.GroupsPrefix = tc.groupsPrefix

			auth := testAuthorization()
			auth.Scopes = append(auth.Scopes, ScopeGroups)
			auth.Claims.Groups = []string{"admins", "devs"}
			auth.ConnectorID = tc.connectorID
			auth.SkipGroupsPrefix = tc.skip

			ts, err := iss.Issue(ctx, auth, "", true)
			require.NoError(t, err)
			require.Equal(t, tc.want, tokenGroups(t, ts.AccessToken))
			require.Equal(t, tc.want, tokenGroups(t, ts.IDToken))

			// The stored refresh token keeps the groups without the prefix, so
			// the tokens of a refresh get it once.
			var rt internal.RefreshToken
			require.NoError(t, internal.Unmarshal(ts.RefreshToken, &rt))
			stored, err := store.GetRefresh(ctx, rt.RefreshId)
			require.NoError(t, err)
			require.Equal(t, []string{"admins", "devs"}, stored.Claims.Groups)
			require.Equal(t, []string{"admins", "devs"}, auth.Claims.Groups)
		})
	}
}
