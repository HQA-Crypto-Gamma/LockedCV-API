# LockedCV-API Email Verification 與 Auth Token 實作計畫

## 問題與目標

- 本週 API 目標是支援「email 驗證註冊」與「token-based API authorization」。
- 註冊流程不應先建立 temporary account row；使用者驗證 email 並回到 App 設定密碼後，API 才建立正式 account。
- API 需要提供 username/email availability check，避免 App 產生註冊 token 前就接受已被使用的資料。
- API 需要寄出 verification email；本計畫暫定由 API 呼叫 email provider，讓 provider API key 留在 API deployment config。
- API authentication 成功時需要回傳 safe account data 加上 auth token。
- 需要用 Bearer auth token 授權會讀取 account resource 的 API routes，避免 App 在 request body/query 放入 requesting user id 或 username。

## 現況分析（2026-05-17）

- 專案：`LockedCV-API`
- 目前已有：
  - `SecureDB`：負責 DB 欄位加密與 keyed hash。
  - `Securable`：提供 `SecureDB` 與 `AuthToken` 共用的 encryption/decryption/hash primitives。
  - `AuthToken`：可建立與載入含 expiration 的 encrypted token。
  - `AuthenticateAccountService` 與 `POST /api/v1/auth/authenticate`。
  - Bearer token parser/current account helper。
  - Account-owned routes 已用 token 檢查 owner 或 admin authorization。
  - Token-scoped current account routes：`GET/PUT /api/v1/account`、`PUT /api/v1/account/password`。
  - Token-scoped owned attachments index：`GET /api/v1/attachments`。
  - `Account` model、password digest、roles、attachments、sensitive data。
  - Account registration 目前仍是 `POST /api/v1/accounts` 直接建立 account。
- 目前尚未有：
  - registration availability endpoint。
  - email provider client/service。
  - broader owned resources endpoint（若 attachments 之外還有其他 resource domain）。

## 設計決策草案

- **Registration token 由 App 建立與驗證**：App 使用 `RegistrationToken` 加密 `username` + `email`，產生回 App 的 verification URL。
- **Verification email 由 API 寄送**：App 把 `username`、`email`、`verification_url` 送到 API，API 呼叫 email provider。原因是 provider API key 比較適合放在 API config/Heroku credentials。
- **不建立 pending account row**：API 只在 App 驗證 token 後收到 username/email/password 時建立正式 account。
- **Auth token 由 API 簽發與驗證**：API 在 authentication success 回傳 token；後續 resource routes 只信任 Bearer token，不信任 App 傳來的 requesting user id。
- **Owned resources index 使用 token 決定 owner**：新增不含 account id 的 owned-resource endpoint，例如 `GET /api/v1/attachments`，由 token 找出 current account 後回傳該 account resources。

## 實作策略（分階段）

1. **Crypto extraction**：先從 `SecureDB` 抽出共用 `Securable` module/class，讓 DB encryption/hash 與 AuthToken 共用 crypto primitive。
2. **Registration availability and email request**：新增 username/email availability check 與 verification email request route/service。
3. **Email provider client**：選定 provider，建立 service object，並用 WebMock 測試 provider request。
4. **AuthToken library**：建立 token payload、加密/簽章、過期時間、decode/verify 流程。
5. **Authentication response update**：登入成功時回傳 `auth_token`。
6. **Bearer authorization helpers**：解析 `Authorization` header，要求格式為 `Bearer <TOKEN>`，建立 current account helper。
7. **Protect resource routes**：針對 account-owned resources 加上 token 檢查；沒有登入/壞 token 回 `401`，有登入但非 owner/admin 回 `403`。
8. **Owned resource index**：新增 token-scoped resource index endpoint，讓 App 不需要送 requesting user id。

## Todo 清單

1. ✅ `securable-crypto-extraction`（已完成）
   - 已從 `SecureDB` 抽出 `Securable`，集中處理 NaCl encryption/decryption、Base64 encoding、key loading。
   - 已保留 `SecureDB.encrypt` / `SecureDB.decrypt` / `SecureDB.hash` public API，避免一次破壞 existing models。
   - 已補 `MSG_KEY` config example 與 `rake newkey:msg`。
   - 已驗證既有 `SecureDB` specs 與完整 API specs 通過。

2. `registration-availability-api`
   - 新增 service：檢查 username 與 email 是否可用。
   - 建議 route：`POST /api/v1/accounts/registration/check`
   - Request 包含 `username`、`email`。
   - Response 可回 `{ "available": true }` 或明確 validation error。
   - username/email 任一已存在時回 `400`，message 保持 user-facing。
   - 最終 `POST /api/v1/accounts` 仍保留 unique constraint handling，避免 check/create race condition。

3. `registration-verification-email-api`
   - 新增 service：接收 `username`、`email`、`verification_url`。
   - 建議 route：`POST /api/v1/accounts/registration/verification`
   - API 再次檢查 username/email availability。
   - 呼叫 email provider 寄出 verification email。
   - 成功回 `202` 或 `200`，不建立 account。
   - 失敗時避免 log plaintext token；email address 可視為 PII，log 要保守。

4. `email-provider-client`
   - 待組內決定 provider：Resend.com、Mailgun、MailTrap 或 Heroku partner provider。
   - 將 provider API key 放在 API config/Heroku credentials，不寫入 repo。
   - 新增 provider client/service object。
   - 用 WebMock mock provider HTTP request。
   - 測試 happy path、provider 4xx/5xx、timeout/network error。

5. ✅ `auth-token-library`（已完成）
   - 已新增 `AuthToken` library。
   - Token envelope 目前包含 payload 與 `exp` expiration timestamp。
   - 已使用 `Securable` 進行 token crypto。
   - 解密失敗、格式錯誤、過期 token 會 raise token-specific errors。
   - 已補 unit specs：encrypted token、round trip、fresh token、expired token、invalid token、tampered token、generated key setup。

6. ✅ `authenticate-response-token`（已完成）
   - 已更新 `POST /api/v1/auth/authenticate` success response，加入 `auth_token`。
   - 已保留 safe account data，不回傳 password/password_digest/encrypted/hash columns。
   - Token payload 目前包含 `account_id`、`username`、`email`，不包含 roles，避免 role changes 造成 stale token claims。
   - 已補 integration/unit specs 確認 token 存在且可被 API verify。
   - 待做：更新 README/Copilot API contract docs。

7. ✅ `bearer-auth-helpers`（已完成）
   - 已新增 request helper 解析 `Authorization` header。
   - 僅接受 `Bearer <TOKEN>`。
   - 缺 header、格式錯誤、token invalid/expired 回 `401`。
   - 已建立 helper：讀取 token payload、確認 resource owner 與 token account 相同、確認 admin caller。

8. ✅ `protect-account-resource-routes`（已完成）
   - 盤點現有需要保護的 routes：
     - account profile read/update/password。
     - attachments list/get/upload/create/masked text/masked export。
     - sensitive data read/create。
   - 已保護 account-owned routes；token account 不等於 path account 時回 `403`。
   - Admin-only routes 已改由 token 找 caller，不再信任 request body/query 的 `current_account_id`。
   - 已補 specs：missing token `401`、invalid token `401`、non-owner/admin `403`、missing target resource `404`。

9. ✅ `owned-resources-index`（已完成 attachments 版本）
   - 已新增 token-scoped attachments index endpoint，避免 App 傳 requesting user id。
   - Route：`GET /api/v1/attachments`
   - API 由 Bearer token 找 current account，再回傳該 account 的 attachment list。
   - 後續如果 resource 不只 attachments，可再新增 `GET /api/v1/resources` 或更清楚的 domain route。
   - 已補 integration specs：只回 token owner resources；沒有 token/錯 token 回 `401`。

## API Contract 草案

### POST `/api/v1/accounts/registration/check`

Request:

```json
{
  "username": "jane_smith",
  "email": "jane@example.com"
}
```

Success `200`:

```json
{
  "available": true
}
```

Failure `400`:

```json
{
  "message": "This user is already registered"
}
```

### POST `/api/v1/accounts/registration/verification`

Request:

```json
{
  "username": "jane_smith",
  "email": "jane@example.com",
  "verification_url": "https://lockedcv-app.example.com/auth/register/verify?token=..."
}
```

Success `202`:

```json
{
  "message": "Verification email sent"
}
```

### POST `/api/v1/auth/authenticate`

Success `200` adds `auth_token`:

```json
{
  "data": {
    "type": "authenticated_account",
    "attributes": {
      "id": "account-uuid",
      "username": "jane_smith",
      "email": "jane@example.com",
      "roles": ["member"],
      "auth_token": "encrypted-token"
    }
  }
}
```

### Authorized resource request

Header:

```text
Authorization: Bearer <TOKEN>
```

Missing or invalid auth returns `401`; authenticated callers without permission return `403`:

```json
{
  "message": "Forbidden"
}
```

## 依賴順序

- `securable-crypto-extraction` -> `auth-token-library`
- `registration-availability-api` -> App registration token flow。
- `registration-verification-email-api` -> `email-provider-client`
- `auth-token-library` -> `authenticate-response-token` -> App token session work。
- `auth-token-library` -> `bearer-auth-helpers` -> `protect-account-resource-routes`
- `bearer-auth-helpers` -> `owned-resources-index`

## 待組內決策

- Email provider 選擇：Resend.com、Mailgun、MailTrap 或其他 Heroku partner provider。
- Provider API key 在 Heroku credentials 中的名稱，以及 provider 要求的 auth header 格式。
- Deployed API 需要設定 `MSG_KEY` Heroku config var；可用 `bundle exec rake newkey:msg` 產生。
- Auth token expiration 長度。
- Auth token payload 是否包含 roles、email、token version、issued-at、capabilities。
- Registration token 是否也要有 expiration（bonus）。
- Owned resources 的正式命名：`attachments`、`resources`、或後續 domain-specific name。
- Admin 是否可以改自己的 role 仍需組內決策；目前既有行為是可以。

## 本週完成定義

- App 可先檢查 username/email 是否可用。
- App 可要求 API 寄出 verification email，且 API 不建立 temporary account。
- API authentication success 回傳 auth token。
- API 可從 `Authorization: Bearer <TOKEN>` 驗證 current account。
- 至少一個 account-owned resource index 不需要 App 傳 requesting user id。
- Email provider call 與 token behavior 都有測試。
