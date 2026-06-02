# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Username rules' do
  it 'HAPPY: builds a username from an email local part' do
    username = LockedCV::UsernameRules.from_email('Vick.Fan@example.com')

    _(username).must_equal 'vick.fan'
  end

  it 'HAPPY: normalizes unsupported characters to separators' do
    username = LockedCV::UsernameRules.from_email('vick fan+test@example.com')

    _(username).must_equal 'vick-fan-test'
  end

  it 'HAPPY: pads short email local parts into a valid SSO username' do
    username = LockedCV::UsernameRules.from_email('vf@example.com')

    _(username).must_equal 'vf-sso'
  end

  it 'SAD: returns nil when no valid username can be built' do
    username = LockedCV::UsernameRules.from_email('使用者@example.com')

    _(username).must_be_nil
  end
end
