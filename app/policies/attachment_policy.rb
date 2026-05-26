# frozen_string_literal: true

module LockedCV
  # Authorization policy for uploaded attachment resources.
  class AttachmentPolicy
    attr_reader :current_account, :attachment

    def initialize(current_account, attachment)
      @current_account = current_account
      @attachment = attachment
    end

    def view?
      owner?
    end

    def view_masked?
      owner? || viewer_masked?
    end

    # Umbrella visibility check for lists/route gates.
    # Use view? for raw/original access and view_masked? for masked output.
    def access?
      view? || view_masked?
    end

    def upload?
      current_account&.member? || current_account&.admin? || false
    end

    def delete?
      owner?
    end

    def owner?
      current_account&.id == attachment&.account_id
    end

    def viewer_masked?
      false
    end

    def summary
      {
        can_view: view?,
        can_view_masked: view_masked?,
        can_access: access?,
        can_upload: upload?,
        can_delete: delete?,
        role: resource_role
      }
    end

    private

    def resource_role
      return 'owner' if owner?
      return 'viewer_masked' if viewer_masked?

      nil
    end
  end
end
