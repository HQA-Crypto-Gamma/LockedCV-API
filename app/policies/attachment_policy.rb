# frozen_string_literal: true

module LockedCV
  # Authorization policy for uploaded attachment resources.
  class AttachmentPolicy
    RESOURCE = 'attachments'

    attr_reader :current_account, :attachment, :auth_scope

    def initialize(current_account, attachment, auth_scope: AuthScope.new())
      @current_account = current_account
      @attachment = attachment
      @auth_scope = auth_scope
    end

    def view?
      can_read? && owner?
    end

    def view_masked?
      can_read? && (owner? || viewer_masked?)
    end

    # Umbrella visibility check for lists/route gates.
    # Use view? for raw/original access and view_masked? for masked output.
    def access?
      view? || view_masked?
    end

    def upload?
      can_write? && (current_account&.member? || current_account&.admin? || false)
    end

    def delete?
      can_write? && owner?
    end

    def owner?
      current_account&.id == attachment&.account_id
    end

    def viewer_masked?
      return false unless current_account && attachment

      AttachmentPermission.where(
        account_id: current_account.id,
        attachment_id: attachment.id,
        role: 'viewer_masked'
      ).any?
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

    def can_read?
      auth_scope.can_read?(RESOURCE)
    end

    def can_write?
      auth_scope.can_write?(RESOURCE)
    end
  end
end
