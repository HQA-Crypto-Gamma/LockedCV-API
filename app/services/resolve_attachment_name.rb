# frozen_string_literal: true

require 'set'

module LockedCV
  # Resolves a user-facing attachment name that is unique within an account.
  class ResolveAttachmentName
    def self.call(account:, filename:)
      new(account:, filename:).call
    end

    def initialize(account:, filename:)
      @account = account
      @filename = filename.to_s.strip
    end

    def call
      return filename unless existing_names.include?(filename)

      numbered_name
    end

    private

    attr_reader :account, :filename

    def existing_names
      @existing_names ||= account.attachments_dataset.select_map(:attachment_name).to_set
    end

    def numbered_name
      extension = File.extname(filename)
      basename = File.basename(filename, extension)

      index = 1
      loop do
        candidate = "#{basename} (#{index})#{extension}"
        return candidate unless existing_names.include?(candidate)

        index += 1
      end
    end
  end
end
