# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Secret credentials not exposed' do
  it 'SECURITY: does not expose database url' do
    _(LockedCV::Api.config.DATABASE_URL).must_be_nil
  end
end
