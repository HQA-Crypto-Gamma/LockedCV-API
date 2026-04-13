# frozen_string_literal: true

require 'json'

module LockedCV
  # Sequel model for files table
  class File < Sequel::Model(:files)
    plugin :timestamps
    plugin :association_dependencies

    many_to_one :user, class: :'LockedCV::User', key: :user_id
    one_to_one :sensitive_data, class: :'LockedCV::SensitiveData', key: :file_id
    add_association_dependencies sensitive_data: :destroy

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'file',
            attributes: {
              id:,
              file_name:,
              route:
            }
          },
          included: {
            user:
          }
        },
        options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
