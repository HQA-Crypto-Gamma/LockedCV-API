# frozen_string_literal: true

require 'json'

module LockedCV
  # Sequel model for users table
  class User < Sequel::Model(:users)
    plugin :timestamps
    plugin :association_dependencies

    one_to_many :files, class: :'LockedCV::File', key: :user_id
    add_association_dependencies files: :destroy

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'user',
            attributes: {
              id:,
              first_name:,
              last_name:,
              phone_number:
            }
          }
        },
        options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
