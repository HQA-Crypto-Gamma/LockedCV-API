# frozen_string_literal: true

require 'json'

module LockedCV
  # Sequel model for attachments table
  class Attachment < Sequel::Model(:attachments)
    plugin :timestamps
    plugin :association_dependencies

    many_to_one :user, class: :'LockedCV::User', key: :user_id
    one_to_one :sensitive_data, class: :'LockedCV::SensitiveData', key: :attachment_id
    add_association_dependencies sensitive_data: :destroy

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'attachment',
            attributes: {
              id:,
              attachment_name:,
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
