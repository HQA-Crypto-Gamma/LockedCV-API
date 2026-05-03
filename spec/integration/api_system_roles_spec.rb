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
    @member_role = LockedCV::Role.create(name: 'member')
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
      "/api/v1/accounts/#{@target.username}/system_roles/member",
      { current_account_id: @admin.id }.to_json,
      req_header
    )

    _(last_response.status).must_equal 201
    _(json_body['message']).must_equal 'System role assigned'
    _(@target.reload.system_roles.map(&:name)).must_include 'member'
  end

  it 'HAPPY: reassigning the same system role is idempotent' do
    @target.add_system_role(@member_role)

    put(
      "/api/v1/accounts/#{@target.username}/system_roles/member",
      { current_account_id: @admin.id }.to_json,
      req_header
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
      { current_account_id: non_admin.id }.to_json,
      req_header
    )

    _(last_response.status).must_equal 403
    _(json_body).must_equal('message' => 'Only admins can manage system roles')
  end

  it 'SAD: rejects unknown system role' do
    put(
      "/api/v1/accounts/#{@target.username}/system_roles/owner",
      { current_account_id: @admin.id }.to_json,
      req_header
    )

    _(last_response.status).must_equal 400
    _(json_body).must_equal('message' => 'Unknown system role')
  end

  it 'SAD: returns 404 for unknown target account' do
    put(
      '/api/v1/accounts/missing-account/system_roles/member',
      { current_account_id: @admin.id }.to_json,
      req_header
    )

    _(last_response.status).must_equal 404
    _(json_body).must_equal('message' => 'Account not found')
  end

  it 'SECURITY: missing current_account_id returns 401' do
    put(
      "/api/v1/accounts/#{@target.username}/system_roles/member",
      {}.to_json,
      req_header
    )

    _(last_response.status).must_equal 401
    _(json_body).must_equal('message' => 'Missing current_account_id')
  end
end
