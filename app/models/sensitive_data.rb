# frozen_string_literal: true

require 'json'

module LockedCV
  # Sequel model for sensitive_data table
  class SensitiveData < Sequel::Model(:sensitive_data)
    plugin :timestamps

    many_to_one :attachment, class: :'LockedCV::Attachment', key: :attachment_id

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'sensitive_data',
            attributes: {
              id:,
              user_name:,
              phone_number:,
              birthday:,
              email:,
              address:,
              identification_numbers:
            }
          }
        },
        options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
