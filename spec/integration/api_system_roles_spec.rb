# frozen_string_literal: true

require_relative '../spec_helper'

describe 'System Role Endpoints' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

  def app
    LockedCV::Api
  end

  before do
    reset_database!
    @admin_role = LockedCV::Role.create(name: 'admin')
    @admin = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].first.transform_keys(&:to_sym)
    )
    @target = LockedCV::CreateAccountService.call(
      account_data: DATA[:accounts].last.transform_keys(&:to_sym)
    )
    @admin.add_system_role(@admin_role)
  end

  it 'HAPPY: admin assigns a system role' do
    put(
      "/api/v1/accounts/#{@target.username}/system_roles/admin",
      {}.to_json,
      auth_req_header(@admin)
    )

    _(last_response.status).must_equal 201
    _(json_body['message']).must_equal 'System role assigned'
    _(@target.reload.system_roles.map(&:name)).must_equal ['admin']
  end

  it 'HAPPY: assigning admin removes the default member role' do
    put(
      "/api/v1/accounts/#{@target.username}/system_roles/admin",
      {}.to_json,
      auth_req_header(@admin)
    )

    _(@target.reload.system_roles.map(&:name)).must_equal ['admin']
    _(@target.member?).must_equal false
    _(@target.admin?).must_equal true
  end

  it 'HAPPY: reassigning the same system role is idempotent' do
    put(
      "/api/v1/accounts/#{@target.username}/system_roles/member",
      {}.to_json,
      auth_req_header(@admin)
    )

    _(last_response.status).must_equal 200
    _(@target.reload.system_roles.count { |role| role.name == 'member' }).must_equal 1
  end

  it 'SAD: non-admin cannot assign a system role' do
    non_admin = LockedCV::CreateAccountService.call(
      account_data: {
        username: 'grace-hopper',
        email: 'grace@example.com',
        phone_number: '0912-000-003',
        password: 'grace-secret'
      }
    )

    put(
      "/api/v1/accounts/#{@target.username}/system_roles/member",
      {}.to_json,
      auth_req_header(non_admin)
    )

    _(last_response.status).must_equal 403
    _(json_body).must_equal('message' => 'Only admins can manage system roles')
  end

  it 'SAD: admin cannot assign their own system role' do
    put(
      "/api/v1/accounts/#{@admin.username}/system_roles/member",
      {}.to_json,
      auth_req_header(@admin)
    )

    _(last_response.status).must_equal 403
    _(json_body).must_equal('message' => 'Admins cannot change their own system role')
  end

  it 'SAD: rejects unknown system role' do
    put(
      "/api/v1/accounts/#{@target.username}/system_roles/owner",
      {}.to_json,
      auth_req_header(@admin)
    )

    _(last_response.status).must_equal 400
    _(json_body).must_equal('message' => 'Unknown system role')
  end

  it 'SAD: returns 404 for unknown target account' do
    put(
      '/api/v1/accounts/missing-account/system_roles/member',
      {}.to_json,
      auth_req_header(@admin)
    )

    _(last_response.status).must_equal 404
    _(json_body).must_equal('message' => 'Account not found')
  end

  it 'SECURITY: missing bearer token returns 401' do
    put(
      "/api/v1/accounts/#{@target.username}/system_roles/member",
      {}.to_json,
      req_header
    )

    _(last_response.status).must_equal 401
    _(json_body).must_equal('message' => 'Missing authorization token')
  end
end
