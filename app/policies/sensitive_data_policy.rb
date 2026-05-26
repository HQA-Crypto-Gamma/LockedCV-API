# frozen_string_literal: true

module LockedCV
  # Authorization policy for sensitive data detected from an attachment.
  class SensitiveDataPolicy
    attr_reader :current_account, :sensitive_data

    def initialize(current_account, sensitive_data)
      @current_account = current_account
      @sensitive_data = sensitive_data
    end

    def view?
      attachment_policy.view?
    end

    def update?
      attachment_policy.owner?
    end

    def delete?
      attachment_policy.owner?
    end

    def summary
      {
        can_view: view?,
        can_update: update?,
        can_delete: delete?
      }
    end

    private

    def attachment_policy
      @attachment_policy ||= AttachmentPolicy.new(current_account, sensitive_data&.attachment)
    end
  end
end
