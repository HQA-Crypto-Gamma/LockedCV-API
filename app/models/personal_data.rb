# frozen_string_literal: true

require 'json'
require 'base64'
require 'rbnacl'

module LockedCV
  STORE_DIR = 'db/local'
  # Holds a full user information
  class PersonalData
    # Create a new personal data entry by passing in hash of attributes
    def initialize(new_personal_data)
      @id = new_personal_data['id'] || new_id
      @first_name = new_personal_data['first_name']
      @last_name = new_personal_data['last_name']
      @phone = new_personal_data['phone']
    end

    attr_reader :id, :first_name, :phone, :last_name

    def to_json(options = {})
      JSON(
        {
          type: 'personal_data',
          id:,
          first_name:,
          last_name:,
          phone:
        },
        options
      )
    end

    # File store must be setup once when application runs
    def self.setup
      FileUtils.mkdir_p(LockedCV::STORE_DIR)
    end

    # Stores personal data in file store
    def save
      File.write("#{LockedCV::STORE_DIR}/#{id}.txt", to_json)
    end

    # Query method to find one personal data entry
    def self.find(find_id)
      personal_data_file = File.read("#{LockedCV::STORE_DIR}/#{find_id}.txt")
      PersonalData.new JSON.parse(personal_data_file)
    end

    # Query method to retrieve index of all personal data entries
    def self.all
      Dir.glob("#{LockedCV::STORE_DIR}/*.txt").map do |file|
        file.match(%r{#{Regexp.quote(LockedCV::STORE_DIR)}/(.*)\.txt})[1]
      end
    end

    private

    def new_id
      timestamp = Time.now.to_f.to_s
      Base64.urlsafe_encode64(RbNaCl::Hash.sha256(timestamp))[0..9]
    end
  end
end
