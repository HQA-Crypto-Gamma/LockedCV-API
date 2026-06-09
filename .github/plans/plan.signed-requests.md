# LockedCV-API Signed Requests 實作計畫

## 問題與目標

- 本週 API 目標是讓 API 能信任呼叫它的 LockedCV-APP，而不是只接受任何格式正確的 JSON。
- Bearer token route 已經有 authentication / authorization；問題主要在使用者登入、註冊、SSO 之前，request 還沒有 auth token。
- 依作業最低要求，所有「無法提供 auth_token 的 POST request」都需要由 App 簽章，API 用 public verify key 驗章。
- 初版採 Ed25519 signing（`rbnacl`），request body 包成：

  ```json
  {
    "data": {},
    "signature": "base64-signature"
  }
  ```

- API 只驗證 request 來源與內容完整性；不在這個 commit 處理 replay protection、signed response、或多 client key registry。

## 現況分析（更新：2026-06-09）

- 專案：`LockedCV-API`
- 目前已有：
  - `rbnacl` 與 `base64` gems。
  - `HttpRequest#body_data`：所有 JSON body 目前直接從 request parse。
  - Google SSO API route：`POST /api/v1/auth/sso`。
  - Auth scope、API key、policy scope gating。
  - `SignedRequest` library foundation。
  - `rake newkey:signing` keypair generator。
  - `config/secrets-example.yml` signed request key placeholders。
  - `HttpRequest#signed_body_data`。
  - Unauthenticated POST route signature enforcement。
  - App-side Google OAuth `state` nonce 已完成，這是 App concern，不需要 API 參與。
- 目前尚未有：
  - App-side signed request sender。
- 目前應優先簽章的 API routes：
  - `POST /api/v1/auth/authenticate`
  - `POST /api/v1/auth/register`
  - `POST /api/v1/auth/sso`
  - `POST /api/v1/accounts/registration/check`
  - `POST /api/v1/accounts`

## 設計決策草案

- **Key topology**：
  - development / production API 只保存 `VERIFY_KEY`。
  - App 保存對應的 `SIGNING_KEY`。
  - test API 可保存一組測試用 `SIGNING_KEY` + `VERIFY_KEY`，讓 API specs 可以產生 signed payload。
  - production API 不應保存 private signing key，避免 API 自己也能偽造 client request。
- **Status code**：
  - malformed JSON / malformed request structure：`400 Bad Request`。
  - missing / invalid signature：`403 Forbidden`，例如 `Must sign request`。
  - authentication failure 本身仍維持既有 `401 Unauthorized`。
- **Route boundary**：
  - 已有 bearer token 的 POST/PUT/DELETE routes 暫時不需要 signing，仍由 auth token + policy 負責。
  - 這次先處理 pre-login / pre-token routes；之後若要防 replay 或支援 third-party client，再另開設計。
- **Payload parsing**：
  - Route 不直接讀 `body_data`，而是讀 `signed_body_data`。
  - `SignedRequest.parse` 驗章成功後只回傳 wrapper 裡的 `data`。
  - App 與 API 必須使用同一套 JSON serialization convention，避免同一個 hash 被序列化成不同字串造成驗章失敗。

## 實作策略（分階段）

1. **Signing library** - done
   - 新增 `app/lib/signed_request.rb`。
   - 提供：
     - `.setup(verify_key64, signing_key64 = nil)`
     - `.generate_keypair`
     - `.parse(signed_request)`
     - `.verify(message, signature64)`
     - `.sign(message)`（只給 test / tooling 使用；production API 未設定 signing key 時應 raise）
   - 使用 `Base64.strict_encode64` / `Base64.strict_decode64`。
   - 補 unit specs：happy path、tampered data、missing signature、bad key、verify-only setup。

2. **Config and secrets** - partially done
   - `config/environments.rb` require `SignedRequest`，並以 `ENV.delete('VERIFY_KEY')` / `ENV.delete('SIGNING_KEY')` setup。
   - `config/secrets-example.yml` 加入：
     - development：`VERIFY_KEY`
     - test：`SIGNING_KEY`、`VERIFY_KEY`
     - production：`VERIFY_KEY`
   - 新增或更新 rake task，例如 `rake newkey:signing`，輸出 `SIGNING_KEY` 與 `VERIFY_KEY`。
   - 確認 env spec 不會把 key 留在 `Api.config`。
   - Remaining：把實際 key 加到 local `config/secrets.yml` 與 Heroku config vars。

3. **HTTP request helper** - done
   - 在 `app/controllers/http_request.rb` 新增：

     ```ruby
     def signed_body_data
       SignedRequest.parse(body_data)
     end
     ```

   - 保留既有 `body_data` 給 bearer-authenticated routes 使用。

4. **Auth routes** - done
   - `app/controllers/auth.rb` route-top 先讀一次 `signed_body_data`。
   - `authenticate`、`register`、`sso` 都使用驗章後的 `@request_data`。
   - `SignedRequest::VerificationError` 回 `403`。
   - 既有 credential / registration / SSO validation error mapping 保持不變。

5. **Account pre-auth routes** - done
   - `POST /api/v1/accounts/registration/check` 改用 `signed_body_data`。
   - `POST /api/v1/accounts` 改用 `signed_body_data`。
   - 這兩個 route 都是在建帳號前使用，無 bearer token，因此應簽章。

6. **Specs** - done
   - 新增 `spec/unit/signed_request_spec.rb` 或依 repo convention 放在對應目錄。
   - 所有呼叫上述 pre-auth POST 的 integration specs 都改成 signed payload。
   - 每一組核心 route 至少補一個 unsigned request -> `403` regression spec。
   - 保留 malformed request -> `400` 的測試，避免簽章錯誤和 request 結構錯誤混在一起。

7. **Manual smoke**
   - API-only：用測試 helper 或 rake console 產生 signed payload，確認 unsigned 會被擋。
   - Cross-repo：APP 更新 signing 後，確認 login、registration、Google SSO 都能跑通。

## API Contract 草案

Unsigned old body：

```json
{
  "username": "vick",
  "password": "password"
}
```

Signed body：

```json
{
  "data": {
    "username": "vick",
    "password": "password"
  },
  "signature": "base64-ed25519-signature"
}
```

Response behavior：

- Valid signature + valid credentials：照既有成功 response。
- Valid signature + bad credentials：照既有 `401`。
- Missing / invalid signature：`403`.
- Malformed wrapper：`400` or `403`，依錯誤類型在 implementation 時固定。

## Out of Scope

- Request replay protection（nonce / timestamp / request id）。
- Signed API responses。
- Signing bearer-authenticated routes。
- 多個 App / mobile client 的 key registry。
- Key rotation UI 或 persisted client key model。

## 完成定義

- API 有 `SignedRequest` library 與 specs。
- `auth.rb` 和 account pre-auth POST routes 都拒絕 unsigned request。
- APP 尚未更新前，這些 routes 會正確回 `403`，而不是 silently accept。
- APP 更新後，login、register、registration email、Google SSO 都能正常使用。
- README / local handoff 後續需要補上 key split、Heroku config vars、manual testing command。

## Commit Message 草案

```text
feat: require signed requests for unauthenticated API posts
```

或若拆成兩個 commits：

```text
feat: add signed request verification
feat: enforce signed pre-auth API routes
```
