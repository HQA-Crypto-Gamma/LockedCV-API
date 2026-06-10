# frozen_string_literal: true

require 'securerandom'

module LockedCV
  # Creates a reusable token for sharing one saved masked attachment.
  class CreateMaskedAttachmentShareLink
    class MaskedAttachmentNotFoundError < StandardError; end

    MAX_TOKEN_ATTEMPTS = 5
    DEFAULT_EXPIRATION_SECONDS = 14 * 24 * 60 * 60

    def self.call(current_account:, attachment_id:, masked_attachment_id:, expires_at: nil)
      new(current_account:, attachment_id:, masked_attachment_id:, expires_at:).call
    end

    def initialize(current_account:, attachment_id:, masked_attachment_id:, expires_at: nil)
      @current_account = current_account
      @attachment_id = attachment_id
      @masked_attachment_id = masked_attachment_id
      @expires_at = expires_at || (Time.now + DEFAULT_EXPIRATION_SECONDS)
    end

    def call
      raise MaskedAttachmentNotFoundError unless current_account
      raise MaskedAttachmentNotFoundError unless masked_attachment

      create_share_link
    end

    private

    attr_reader :current_account, :attachment_id, :masked_attachment_id, :expires_at

    def masked_attachment
      @masked_attachment ||= MaskedAttachment.first(
        id: masked_attachment_id.to_s,
        attachment_id: attachment_id.to_s
      )
    end

    def create_share_link
      MAX_TOKEN_ATTEMPTS.times do
        return MaskedAttachmentShareLink.create(share_link_data)
      rescue Sequel::UniqueConstraintViolation
        next
      end

      raise Sequel::UniqueConstraintViolation
    end

    def share_link_data
      {
        token: SecureRandom.urlsafe_base64(32),
        attachment_id: attachment_id.to_s,
        masked_attachment_id: masked_attachment_id.to_s,
        creator_account_id: current_account.id,
        expires_at:
      }
    end
  end
end
