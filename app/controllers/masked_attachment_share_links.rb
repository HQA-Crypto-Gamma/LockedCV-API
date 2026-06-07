# frozen_string_literal: true

require 'roda'
require_relative 'app'

module LockedCV
  # API routes for redeeming masked attachment share links.
  class Api < Roda
    route('masked_attachment_share_links') do |routing|
      current_account = current_account!(routing)

      routing.on String do |token|
        routing.on 'redeem' do
          # POST api/v1/masked_attachment_share_links/[token]/redeem
          routing.post do
            redemption = RedeemMaskedAttachmentShareLink.call(current_account:, token:)

            { message: 'Masked attachment share link redeemed', data: redemption }.to_json
          rescue RedeemMaskedAttachmentShareLink::ShareLinkNotFoundError
            routing.halt 404, { message: 'Masked attachment share link not found' }.to_json
          rescue StandardError => e
            Api.logger.error "MASKED ATTACHMENT SHARE LINK REDEEM ERROR: #{e.message}"
            routing.halt 400, { message: 'Could not redeem masked attachment share link' }.to_json
          end
        end
      end
    end
  end
end
