# frozen_string_literal: true

require_relative 'spec_helper'

DATA = {} # rubocop:disable Style/MutableConstant
DATA[:personal_data] = YAML.safe_load_file('db/seeds/personal_data_seeds.yml')

describe 'Test Personal Data Handling' do
  include Rack::Test::Methods
  include LockedCV::SpecHelpers

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
    wipe_database_tables!
    LockedCV::PersonalData.setup
    Dir.glob('db/local/*.txt').each { |file| File.delete(file) }

    seeded_personal_data.each do |personal_data|
      LockedCV::PersonalData.new(personal_data).save_changes
    end
  end

  describe 'GET /api/v1/personal_data' do
    it 'HAPPY: should be able to get list of all personal data ids' do
      LockedCV::PersonalData.new(DATA[:personal_data][0]).save_changes
      LockedCV::PersonalData.new(DATA[:personal_data][1]).save_changes

      get '/api/v1/personal_data'
      _(last_response.status).must_equal 200

      result = JSON.parse(last_response.body)
      _(result['personal_data_ids'].count).must_equal 2
    end

    it 'HAPPY: should return the expected personal data ids' do
      get '/api/v1/personal_data'

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(JSON.parse(last_response.body)['personal_data_ids'].sort).must_equal %w[pd_001 pd_002]
    end
  end

  describe 'GET /api/v1/personal_data/:id' do
    it 'HAPPY: should be able to get details of a single personal data record' do
      existing_personal_data = seeded_personal_data[0]
      id = existing_personal_data['id']

      get "/api/v1/personal_data/#{id}"

      _(last_response.status).must_equal 200
      _(last_response.headers['Content-Type']).must_include 'application/json'

      result = JSON.parse(last_response.body)
      _(result['type']).must_equal 'personal_data'
      _(result['id']).must_equal id
      _(result['first_name']).must_equal existing_personal_data['first_name']
      _(result['last_name']).must_equal existing_personal_data['last_name']
      _(result['phone']).must_equal existing_personal_data['phone']
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
    it 'HAPPY: should be able to create new personal data' do
      new_personal_data = {
        first_name: 'Grace',
        last_name: 'Hopper',
        phone: '987-654-3210'
      }

      req_header = { 'CONTENT_TYPE' => 'application/json' }
      post '/api/v1/personal_data', new_personal_data.to_json, req_header

      _(last_response.status).must_equal 201
      _(last_response.headers['Content-Type']).must_include 'application/json'

      response_body = JSON.parse(last_response.body)
      created_id = response_body['id']
      _(response_body['message']).must_equal 'Personal data saved'
      _(created_id).wont_be_nil

      saved_record = JSON.parse(File.read("db/local/#{created_id}.txt"))
      _(saved_record).must_equal(
        'type' => 'personal_data',
        'id' => created_id,
        'first_name' => 'Grace',
        'last_name' => 'Hopper',
        'phone' => '987-654-3210'
      )
    end

    it 'SAD: should return 400 for invalid personal data payload' do
      req_header = { 'CONTENT_TYPE' => 'application/json' }
      post '/api/v1/personal_data', '{bad json', req_header

      _(last_response.status).must_equal 400
      _(last_response.headers['Content-Type']).must_include 'application/json'
      _(JSON.parse(last_response.body)).must_equal(
        'message' => 'Could not save personal data'
      )
    end
  end
end
