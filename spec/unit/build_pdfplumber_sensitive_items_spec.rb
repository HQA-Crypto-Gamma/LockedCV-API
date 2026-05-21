# frozen_string_literal: true

require_relative '../spec_helper'

describe 'BuildPdfplumberSensitiveItems' do
  it 'HAPPY: skips blank match values and deduplicates string-normalized keys' do
    matches = [
      { type: :email, value: 'alan@example.com', source: :pattern },
      { type: :email, value: 'alan@example.com', source: 'pattern' },
      { type: :phone_number, value: '   ', source: :pattern },
      { type: :identification_numbers, value: 'B987654321', source: :sensitive_data }
    ]

    items = LockedCV::BuildPdfplumberSensitiveItems.call(matches:, sensitive_data: nil)

    _(items).must_equal(
      [
        {
          field_name: 'email',
          value: 'alan@example.com',
          kind: 'email',
          label: 'EMAIL'
        },
        {
          field_name: 'identification_numbers',
          value: 'B987654321',
          kind: 'id_number',
          label: 'ID'
        }
      ]
    )
  end
end
