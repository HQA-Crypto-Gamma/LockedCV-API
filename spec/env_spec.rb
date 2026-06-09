# frozen_string_literal: true

require_relative 'spec_helper'

describe 'Secret credentials not exposed' do
  it 'SECURITY: does not expose database url' do
    _(LockedCV::Api.config.DATABASE_URL).must_be_nil
  end

  it 'SECURITY: does not expose database key' do
    _(LockedCV::Api.config.DB_KEY).must_be_nil
  end

  it 'SECURITY: does not expose signed request keys' do
    _(LockedCV::Api.config.SIGNING_KEY).must_be_nil
    _(LockedCV::Api.config.VERIFY_KEY).must_be_nil
  end
end
