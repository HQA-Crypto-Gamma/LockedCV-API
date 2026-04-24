# frozen_string_literal: true

module LockedCV
  # Finds sensitive data for a specific attachment
  class FindSensitiveDataService
    def self.call(attachment_id:)
      SensitiveData.where(attachment_id: attachment_id.to_s).first
    end
  end
end
