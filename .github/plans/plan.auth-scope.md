# LockedCV-API Auth Scope 與 Google SSO 實作計畫

## 問題與目標

- 本週 API 目標是支援 scoped authorization tokens 與 Google OAuth 2.0 / OIDC SSO。
- Scoped authorization 讓 API 可以簽發不同權限範圍的 auth token：
  - 一般登入 session token 預設給 full access scope：`*:write`。
  - 使用者 API key 給 limited read scope：`*:read`。
- Policy objects 需要同時考慮 current account、resource、以及 auth scope。
- Service/controller 需要從 auth token 解析出 `auth_scope`，再傳給 policy object。
- API 需要提供 limited-scope account details route：`GET /api/v1/accounts/:username`，讓使用者可用 API key 從 CLI 測試讀取有限資料。
- Google SSO 採課程建議的 solution 3：App 完成 OAuth browser flow 並取得 Google `id_token`，API 接收 `id_token` 與 JWKS 後驗證，建立或找到 account，回傳 account 與 API auth token。

## 現況分析（更新：2026-06-01）

- 專案：`LockedCV-API`
- 目前已有：
  - `AuthScope`：解析 `*:write`、`*:read` 與 resource-specific scope；`write` implies `read`。
  - `AuthToken`：encrypted token，identity payload 與 scope 分開存；missing scope token 視為 invalid。
  - Request-level auth context：`HttpRequest#authorized_account` 建立 `AuthorizedAccount`，`app.rb` 在每個 request 開頭解析 bearer token。
  - `AuthenticateAccountService`：帳密登入後回傳 account data 與 auth token。
  - `AccountPolicy`、`AttachmentPolicy`、`SensitiveDataPolicy` 與 scopes。
  - `AccountPolicy`、`AttachmentPolicy` 已接 `auth_scope:`，read/write action 會依 scope gating。
  - 高風險 write services 已接 scope 並做最終授權：profile update、password change、system-role assignment、account deletion、attachment upload、attachment deletion。
  - Attachment index/show response 已回傳 per-resource `policy` summary。
  - Account profile current route：`GET /api/v1/account`。
  - Limited-scope route：`GET /api/v1/accounts/:username` 回傳 `authorized_account` envelope，包含 safe account detail 與 `*:read` API key。
- 目前尚未有：
  - Google OIDC `id_token` verification service。
  - `POST /api/v1/auth/sso` route。
  - SSO account provisioning / lookup strategy。

## 設計決策草案

- **Scope string 格式**：採 whitespace-separated scope tokens，例如：

  ```text
  *:write
  *:read
  accounts:read attachments:read
  attachments:read attachments:delete
  ```

- **Session token default scope**：帳密登入與 SSO 登入回傳的 session token 預設 full access：`*:write`。
- **API key scope**：account detail route 產生 read-only API key：`*:read`。
- **AuthScope library**：集中 parse/normalize/check scope，避免 policies 自己 split string。
- **Policy 初始化**：新增 optional auth scope 參數，例如：

  ```ruby
  AttachmentPolicy.new(current_account, attachment, auth_scope:)
  AccountPolicy.new(current_account, target_account, auth_scope:)
  ```

- **Full scope shortcut**：`*:write` 允許既有 full session token 維持目前行為，且 `write` implies `read`。
- **Read scope meaning**：`*:read` 或 `resource:read` 只允許 read/view/index 類動作，不允許 update/delete/upload。
- **Backward compatibility**：舊 token 沒有 scope 時會被視為 invalid token；App 需要清掉舊 session 或讓使用者重新登入。
- **Google SSO 驗證責任**：API 不做 browser redirect；API 接收 App 傳來的 `id_token` 與 JWKS，驗證 signature、issuer、audience、expiration 後才信任 email/profile。
- **SSO username strategy**：初版可由 Google email local-part normalize 產生 username，若撞名則加 suffix；或只以 email 找 account，username 另由 API 生成。需組內決策。

## 實作策略（分階段）

1. **AuthScope library**：已完成。
2. **AuthToken scope payload**：已完成；session token default `*:write`。
3. **Bearer helper extraction**：已完成；request-level `AuthorizedAccount` context。
4. **Policy scope adoption**：已完成 Account/Attachment policies。
5. **Limited API key route/response**：已完成 `GET /api/v1/accounts/:username`。
6. **Service-level scope enforcement**：已完成主要 write services。
7. **Limited account details route CLI testing**：已完成，可用 `*:read` API key 呼叫 GET routes。
8. **SSO id token verification service**：用 `http` / `jwt` gems 解析和驗證 Google `id_token`。
9. **SSO auth route**：新增 `POST /api/v1/auth/sso`，驗證 Google identity、建立或找到 account、回傳 session token。
10. **Tests and docs**：scope/API-key specs 已補；SSO specs/docs 待補。

## Todo 清單

1. `auth-scope-library` - done
   - 新增 `app/lib/auth_scope.rb`。
   - 支援 parse string，例如 `*:read`、`*:write`、`accounts:read attachments:read`。
   - 提供 predicates：
     - `can_read?(resource)`
     - `can_write?(resource)`
   - `write` implies `read`。
   - 補 unit specs：wildcard、resource-specific、multiple scopes。

2. `auth-token-scope-payload` - done
   - 更新 `AuthToken` token payload convention，加入 `scope`。
   - `AuthenticateAccountService` 簽發 session token 時使用 full access scope：`*:write`。
   - Scope 存在 encrypted token envelope，沒有塞進 identity payload。
   - 補 specs 確認新 token 包含 scope。
   - 舊 token missing scope 視為 invalid token。

3. `bearer-auth-scope-extraction` - done
   - Bearer auth helper 解析 token 後建立 current auth context：

     ```ruby
     @auth
     @auth_account
     ```

   - `HttpRequest#authorized_account` 回傳 `AuthorizedAccount`。
   - Missing/invalid/malformed token 回 `401`。
   - 補 integration specs：missing scope token、read-only token、full token。

4. `policy-auth-scope-adoption` - partially done
   - 更新 `AccountPolicy`、`AttachmentPolicy` 接 `auth_scope:`。
   - Policy predicate 同時判斷 resource ownership/permission 與 scope 是否允許該 action。
   - Read-only API key 應允許：
     - account details read。
     - attachment index/show read。
     - masked read 若 resource policy 允許。
   - Read-only API key 應拒絕：
     - profile update。
     - password update。
     - upload。
     - delete。
     - sensitive data create/update。
   - 補 policy specs 固定 full/read-only 行為。
   - `SensitiveDataPolicy` 後續可再獨立接 scope；目前 sensitive-data routes 先透過 `AttachmentPolicy` gate。

5. `limited-api-key-account-response` - done
   - 在 account detail route 中加入 limited API key。
   - 初版可每次 response 產生 deterministic duration token；若要 revoke/rotate，後續再建 persisted API keys table。
   - Response envelope：

     ```json
     {
       "data": {
         "type": "authorized_account",
         "attributes": {
           "account": {},
           "auth_token": "encrypted-read-only-token"
         }
       }
     }
     ```

   - 避免 log API key。
   - Specs 確認 token 可被 `AuthToken.load` 解析出 expected scope。

6. `limited-account-details-route` - done
   - 新增 route：`GET /api/v1/accounts/:username`。
   - Bearer token 可以是 limited API key。
   - Policy 允許 `accounts:read` 或 `*:read` 時讀取 safe account data。
   - 不回傳 encrypted/hash/password columns。
   - 無 permission 或隱藏不存在/不可見 account 回 `404`。
   - 補 CLI-friendly README example：

     ```bash
     http GET :9000/api/v1/accounts/ada-lovelace Authorization:"Bearer $API_KEY"
     ```

7. `google-sso-token-verifier`
   - 新增 service，例如 `VerifyGoogleIdToken` 或 `AuthenticateSsoAccount`。
   - 只用 `http` 與 `jwt` gems，不使用 Google packaged gems。
   - 驗證：
     - `iss` 是 Google issuer。
     - `aud` 等於 API/App 設定的 `GOOGLE_CLIENT_ID`。
     - `exp` 未過期。
     - signature 可由 JWKS 驗證。
     - email present，必要時檢查 `email_verified`。
   - Specs 使用固定 JWKS/test JWT，不打真實 Google。

8. `auth-sso-route`
   - 新增 `POST /api/v1/auth/sso`。
   - Request 初版由 App 傳：

     ```json
     {
       "provider": "google",
       "id_token": "...",
       "jwks": {}
     }
     ```

   - API 驗證 `id_token` 後找 account：
     - 先用 email hash 找 existing account。
     - 不存在則建立 SSO account。
   - 回傳格式與 `POST /auth/authenticate` 一致，包含 full-scope session auth token。
   - 補 integration specs：new SSO account、existing account、invalid token、wrong audience、expired token。

9. `sso-account-provisioning`
   - 決定 SSO account 的 required fields：
     - username。
     - email。
     - password_digest 是否允許 nil 或產生 random unusable password。
     - roles default member。
   - 若 `accounts.password_digest` 不允許 nil，建立 random locked password 或調整 schema需另開 migration。
   - 若 Google name/avatar 需要保存，需先決定 schema；初版可不存 avatar。

10. `docs-and-handoff`
    - 更新 README API contract。
    - 更新 `.github/copilot-instructions.md`。
    - 更新 `local.md` handoff notes。
    - 記錄 Heroku config vars：
      - `GOOGLE_CLIENT_ID`
      - 可能的 issuer/JWKS config。

## API Contract 草案

### Session token scope

`POST /api/v1/auth/authenticate` success token envelope includes scope outside
the identity payload:

```json
{
  "payload": {
    "account_id": "account-uuid",
    "username": "ada-lovelace",
    "email": "ada@example.com"
  },
  "scope": "*:write",
  "exp": 1234567890
}
```

### Limited account API key

`GET /api/v1/accounts/:username`:

```json
{
  "data": {
    "type": "authorized_account",
    "attributes": {
      "account": {
        "data": {
          "type": "account",
          "attributes": {
            "id": "account-uuid",
            "username": "ada-lovelace",
            "email": "ada@example.com"
          }
        }
      },
      "auth_token": "encrypted-read-only-token"
    }
  }
}
```

The returned token has `scope: "*:read"` in its encrypted envelope.

### GET `/api/v1/accounts/:username`

Header:

```text
Authorization: Bearer <limited-api-key>
```

Success `200`:

```json
{
  "data": {
    "type": "authorized_account",
    "attributes": {
      "account": {},
      "auth_token": "encrypted-read-only-token"
    }
  }
}
```

### POST `/api/v1/auth/sso`

Request:

```json
{
  "provider": "google",
  "id_token": "<google-id-token>",
  "jwks": {
    "keys": []
  }
}
```

Success `200` or `201`:

```json
{
  "data": {
    "type": "authenticated_account",
    "attributes": {
      "id": "account-uuid",
      "username": "ada-lovelace",
      "email": "ada@example.com",
      "roles": ["member"],
      "auth_token": "full-scope-session-token"
    }
  }
}
```

## 依賴順序

- `auth-scope-library` -> `auth-token-scope-payload`
- `auth-token-scope-payload` -> `bearer-auth-scope-extraction`
- `bearer-auth-scope-extraction` -> `policy-auth-scope-adoption`
- `policy-auth-scope-adoption` -> `limited-account-details-route`
- `limited-api-key-account-response` -> APP `plan.account-api-token.md`
- APP OAuth flow -> API `auth-sso-route`
- `google-sso-token-verifier` -> `auth-sso-route`

## 待組內決策

- API key 是否每次 account response 動態產生，或建立 persisted API keys table 以支援 revoke/rotate。
- Limited token expiration 長度。
- `GET /api/v1/accounts/:username` 目前允許 self 或 admin view。若 admin view 其他 account，回傳 token 代表 target account 且仍為 read-only；是否保留此語意可再決策。
- SSO account username 產生規則。
- SSO account 是否需要可設定本地 password。
- App 傳 JWKS 給 API，或 API 自行從 Google JWKS endpoint fetch/cache；作業文字傾向 App 傳 JWKS。
- SSO failure status：invalid token 用 `401` 還是 malformed request 用 `400`。

## 本週完成定義

- API 有 `AuthScope` library 並有 unit specs。
- 所有新 `AuthToken` 都包含 scope；session token 預設 `*:write`。
- Limited API key 可以從 account view 取得，並能從 CLI 呼叫 limited read route。
- Policies 能根據 auth scope 拒絕 read-only token 的 write/delete/upload actions。
- `GET /api/v1/accounts/:username` 支援 limited-scope token 並有 specs。
- `POST /api/v1/auth/sso` 能驗證 Google `id_token`，建立或找到 account，回傳 full-scope session token。
- README / copilot / local docs 說明 scope 與 SSO contract。
