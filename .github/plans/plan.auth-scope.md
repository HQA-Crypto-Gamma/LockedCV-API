# LockedCV-API Auth Scope 與 Google SSO 實作計畫

## 問題與目標

- 本週 API 目標是支援 scoped authorization tokens 與 Google OAuth 2.0 / OIDC SSO。
- Scoped authorization 讓 API 可以簽發不同權限範圍的 auth token：
  - 一般登入 session token 預設給 full access scope。
  - 使用者 API key 給 limited scope，例如 `account:read attachments:read` 或 `*:read`。
- Policy objects 需要同時考慮 current account、resource、以及 auth scope。
- Service/controller 需要從 auth token 解析出 `auth_scope`，再傳給 policy object。
- API 需要提供 limited-scope account details route，例如 `GET /api/v1/account/:username`，讓使用者可用 API key 從 CLI 測試讀取有限資料。
- Google SSO 採課程建議的 solution 3：App 完成 OAuth browser flow 並取得 Google `id_token`，API 接收 `id_token` 與 JWKS 後驗證，建立或找到 account，回傳 account 與 API auth token。

## 現況分析（2026-05-31）

- 專案：`LockedCV-API`
- 目前已有：
  - `AuthToken`：encrypted token，payload 目前包含 `account_id`、`username`、`email` 與 `exp`。
  - `current_account!` / Bearer token helpers：protected routes 可從 token 找 current account。
  - `AuthenticateAccountService`：帳密登入後回傳 account data 與 auth token。
  - `AccountPolicy`、`AttachmentPolicy`、`SensitiveDataPolicy` 與 scopes。
  - Attachment index/show response 已回傳 per-resource `policy` summary。
  - Account profile current route：`GET /api/v1/account`。
- 目前尚未有：
  - Auth scope string parser / library。
  - Token payload 的 `scope` / `auth_scope` 欄位。
  - Limited-scope API key generation route/response。
  - Policies 對 auth scope 的解讀。
  - `GET /api/v1/account/:username` limited-scope route。
  - Google OIDC `id_token` verification service。
  - `POST /api/v1/auth/sso` route。
  - SSO account provisioning / lookup strategy。

## 設計決策草案

- **Scope string 格式**：先採 whitespace-separated scope tokens，例如：

  ```text
  *:full
  *:read
  account:read attachments:read
  attachments:read attachments:delete
  ```

- **Session token default scope**：帳密登入與 SSO 登入回傳的 session token 預設 full access，例如 `*:full`。
- **API key scope**：account view 產生或顯示 read-only API key，初版可用 `account:read attachments:read` 或 `*:read`。
- **AuthScope library**：集中 parse/normalize/check scope，避免 policies 自己 split string。
- **Policy 初始化**：新增 optional auth scope 參數，例如：

  ```ruby
  AttachmentPolicy.new(current_account, attachment, auth_scope:)
  AccountPolicy.new(current_account, target_account, auth_scope:)
  ```

- **Full scope shortcut**：`*:full` 允許既有 session token 維持目前行為。
- **Read scope meaning**：`*:read` 或 `resource:read` 只允許 read/view/index 類動作，不允許 update/delete/upload。
- **Backward compatibility**：舊 token 沒有 scope 時要明確處理：
  - production/user session 建議讓 App 清掉舊 session。
  - API loader 可短期把 missing scope 視為 invalid token 或 full scope，需組內決定。
- **Google SSO 驗證責任**：API 不做 browser redirect；API 接收 App 傳來的 `id_token` 與 JWKS，驗證 signature、issuer、audience、expiration 後才信任 email/profile。
- **SSO username strategy**：初版可由 Google email local-part normalize 產生 username，若撞名則加 suffix；或只以 email 找 account，username 另由 API 生成。需組內決策。

## 實作策略（分階段）

1. **AuthScope library**：建立 scope parser 與 predicate API。
2. **AuthToken scope payload**：所有新 token payload 加入 scope；session token default full scope。
3. **Bearer helper extraction**：current account helper 同時抽出 auth scope，供 controllers/services/policies 使用。
4. **Policy scope adoption**：先從 Account/Attachment policies 接 `auth_scope`，讓 read/write/delete/upload 依 scope 限制。
5. **Limited API key route/response**：讓 current account 可以取得 limited-scope API key。
6. **Limited account details route**：新增 `GET /api/v1/account/:username`，用 limited token 測 read-only account details。
7. **SSO id token verification service**：用 `http` / `jwt` gems 解析和驗證 Google `id_token`。
8. **SSO auth route**：新增 `POST /api/v1/auth/sso`，驗證 Google identity、建立或找到 account、回傳 session token。
9. **Tests and docs**：補 unit/integration specs、README/copilot/local docs。

## Todo 清單

1. `auth-scope-library`
   - 新增 `app/lib/auth_scope.rb`。
   - 支援 parse string，例如 `*:read`、`*:full`、`attachments:read account:read`。
   - 提供 predicates：
     - `full?`
     - `allows?(resource, action)`
     - `allows_read?(resource)`
     - `allows_write?(resource)` 或明確 `create/update/delete`。
   - 對 malformed scope raise clear error。
   - 補 unit specs：wildcard、resource-specific、multiple scopes、unknown/malformed scope。

2. `auth-token-scope-payload`
   - 更新 `AuthToken` token payload convention，加入 `scope`。
   - `AuthenticateAccountService` 簽發 session token 時使用 full access scope。
   - 建立 helper method，例如 `AuthToken.for_session(account)`、`AuthToken.for_api_key(account, scope:)`，避免 payload 格式散落。
   - 補 specs 確認新 token 包含 scope。
   - 決定舊 token missing scope 要 invalid 還是 fallback。

3. `bearer-auth-scope-extraction`
   - Bearer auth helper 解析 token 後建立 current auth context：

     ```ruby
     current_account
     current_auth_scope
     ```

   - Controllers 不直接 parse token payload。
   - 針對 missing/invalid/malformed scope 回 `401` 或 `403` 的規則需固定。
   - 補 integration specs：missing scope token、read-only token、full token。

4. `policy-auth-scope-adoption`
   - 更新 `AccountPolicy`、`AttachmentPolicy`、`SensitiveDataPolicy` 接 `auth_scope:`。
   - Policy predicate 先判斷 resource ownership/permission，再判斷 scope 是否允許該 action。
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

5. `limited-api-key-account-response`
   - 在 current account response 或 account profile route 中加入 limited API key。
   - 初版可每次 response 產生 deterministic duration token；若要 revoke/rotate，後續再建 persisted API keys table。
   - 建議 response 欄位：

     ```json
     {
       "api_key": "encrypted-limited-token",
       "api_key_scope": "account:read attachments:read"
     }
     ```

   - 避免 log API key。
   - Specs 確認 token 可被 `AuthToken.load` 解析出 expected scope。

6. `limited-account-details-route`
   - 新增 route：`GET /api/v1/account/:username`。
   - Bearer token 可以是 limited API key。
   - Policy 允許 `account:read` 或 `*:read` 時讀取 safe account data。
   - 不回傳 encrypted/hash/password columns。
   - 若 caller 無 scope 或無 permission，回 `403`；若隱藏不存在/不可見 account，視設計可回 `404`。
   - 補 CLI-friendly README example：

     ```bash
     http GET :9000/api/v1/account/ada-lovelace Authorization:"Bearer $API_KEY"
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

`POST /api/v1/auth/authenticate` success token payload should include:

```json
{
  "payload": {
    "account_id": "account-uuid",
    "username": "ada-lovelace",
    "email": "ada@example.com",
    "scope": "*:full"
  },
  "exp": 1234567890
}
```

### Limited account API key

Potential field on `GET /api/v1/account`:

```json
{
  "data": {
    "type": "account",
    "attributes": {
      "id": "account-uuid",
      "username": "ada-lovelace",
      "email": "ada@example.com",
      "api_key": "encrypted-token",
      "api_key_scope": "account:read attachments:read"
    }
  }
}
```

### GET `/api/v1/account/:username`

Header:

```text
Authorization: Bearer <limited-api-key>
```

Success `200`:

```json
{
  "data": {
    "type": "account",
    "attributes": {
      "username": "ada-lovelace",
      "email": "ada@example.com"
    }
  },
  "policy": {
    "can_view": true
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

- Scope string 是否採 `*:read` / `*:full`，或教授 demo 另有命名。
- Missing scope 的舊 auth token 要視為 invalid，還是短期 fallback full scope。
- API key 是否每次 account response 動態產生，或建立 persisted API keys table 以支援 revoke/rotate。
- Limited token expiration 長度。
- `GET /api/v1/account/:username` 是否允許 read-only token 看其他使用者，或只看 token owner。
- SSO account username 產生規則。
- SSO account 是否需要可設定本地 password。
- App 傳 JWKS 給 API，或 API 自行從 Google JWKS endpoint fetch/cache；作業文字傾向 App 傳 JWKS。
- SSO failure status：invalid token 用 `401` 還是 malformed request 用 `400`。

## 本週完成定義

- API 有 `AuthScope` library 並有 unit specs。
- 所有新 `AuthToken` 都包含 scope；session token 預設 full scope。
- Limited API key 可以從 account view 取得，並能從 CLI 呼叫 limited read route。
- Policies 能根據 auth scope 拒絕 read-only token 的 write/delete/upload actions。
- `GET /api/v1/account/:username` 支援 limited-scope token 並有 specs。
- `POST /api/v1/auth/sso` 能驗證 Google `id_token`，建立或找到 account，回傳 full-scope session token。
- README / copilot / local docs 說明 scope 與 SSO contract。
