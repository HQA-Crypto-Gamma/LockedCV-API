# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::Api do
  include Rack::Test::Methods

  def app
    LockedCV::Api
  end

  describe 'GET /' do
    it 'HAPPY: should return API status as JSON' do
      get '/'

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(JSON.parse(last_response.body)).must_equal(
        'message' => 'LockedCV API up at /api/v1'
      )
    end

    it 'SECURITY: rejects requests that do not match configured secure scheme' do
      get '/', {}, 'rack.url_scheme' => 'https'

      _(last_response.status).must_equal 403
      _(JSON.parse(last_response.body)).must_equal(
        'message' => 'TLS/SSL Required'
      )
    end
  end
end
