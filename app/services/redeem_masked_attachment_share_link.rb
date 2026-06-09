# frozen_string_literal: true

module LockedCV
  # Redeems a masked attachment share token into access to one masked PDF.
  class RedeemMaskedAttachmentShareLink
    class ShareLinkNotFoundError < StandardError; end

    ROLE = 'viewer'

    def self.call(current_account:, token:)
      new(current_account:, token:).call
    end

    def initialize(current_account:, token:)
      @current_account = current_account
      @token = token
    end

    def call
      raise ShareLinkNotFoundError unless current_account && share_link&.active?

      grant_permission unless owner?
      redemption
    end

    private

    attr_reader :current_account, :token

    def share_link
      @share_link ||= MaskedAttachmentShareLink.first(token: token.to_s)
    end

    def owner?
      raise ShareLinkNotFoundError unless share_link.attachment

      current_account.id == share_link.attachment.account_id
    end

    def grant_permission
      permission || create_permission
    rescue Sequel::UniqueConstraintViolation
      permission
    end

    def permission
      @permission ||= MaskedAttachmentPermission.first(permission_data)
    end

    def create_permission
      @permission = MaskedAttachmentPermission.create(permission_data)
    end

    def permission_data
      {
        attachment_id: share_link.attachment_id,
        masked_attachment_id: share_link.masked_attachment_id,
        account_id: current_account.id,
        role: ROLE
      }
    end

    def redemption
      {
        type: 'masked_attachment_share_link_redemption',
        attributes: {
          attachment_id: share_link.attachment_id,
          masked_attachment_id: share_link.masked_attachment_id,
          role: ROLE
        }
      }
    end
  end
end
