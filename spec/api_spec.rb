# frozen_string_literal: true

require_relative 'spec_helper'

describe LockedCV::Api do
  include Rack::Test::Methods

  def app
    LockedCV::Api
  end

  def seed_file
    'db/seeds/personal_data_seeds.yml'
  end

  def seeded_personal_data
    YAML.safe_load_file(seed_file)
  end

  before do
    LockedCV::PersonalData.setup
    Dir.glob('db/local/*.txt').each { |file| File.delete(file) }

    seeded_personal_data.each do |personal_data|
      LockedCV::PersonalData.new(personal_data).save_changes
    end
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
  end

  describe 'GET /api/v1/personal_data' do
    it 'HAPPY: should return all stored personal data ids' do
      get '/api/v1/personal_data'

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(JSON.parse(last_response.body)['personal_data_ids'].sort).must_equal %w[pd_001 pd_002]
    end
  end

  describe 'GET /api/v1/personal_data/:id' do
    it 'HAPPY: should return the requested personal data record' do
      get '/api/v1/personal_data/pd_001'

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(JSON.parse(last_response.body)).must_equal(
        'type' => 'personal_data',
        'id' => 'pd_001',
        'first_name' => 'Ada',
        'last_name' => 'Lovelace',
        'phone' => '123-456-7890'
      )
    end

    it 'SAD: should return 404 for an unknown personal data id' do
      get '/api/v1/personal_data/not_real'

      _(last_response.status).must_equal 404
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(JSON.parse(last_response.body)).must_equal(
        'message' => 'Personal data not found'
      )
    end
  end

  describe 'POST /api/v1/personal_data' do
    it 'HAPPY: should create a new personal data record' do
      payload = {
        first_name: 'Grace',
        last_name: 'Hopper',
        phone: '987-654-3210'
      }

      post '/api/v1/personal_data', JSON.generate(payload), 'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'

      response_body = JSON.parse(last_response.body)
      _(response_body['message']).must_equal 'Personal data saved'
      _(response_body['id']).wont_be_nil

      saved_record = JSON.parse(File.read("db/local/#{response_body['id']}.txt"))
      _(saved_record).must_equal(
        'type' => 'personal_data',
        'id' => response_body['id'],
        'first_name' => 'Grace',
        'last_name' => 'Hopper',
        'phone' => '987-654-3210'
      )
    end
  end
end
