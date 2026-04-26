# frozen_string_literal: true

require_relative '../spec_helper'

describe LockedCV::Password do
  it 'SECURITY: digests password with random salt' do
    digest_1 = LockedCV::Password.digest('super-secret').to_s
    digest_2 = LockedCV::Password.digest('super-secret').to_s

    _(digest_1).wont_equal digest_2
  end

  it 'SECURITY: verifies correct password from digest' do
    digest = LockedCV::Password.digest('super-secret')

    _(digest.correct?('super-secret')).must_equal true
    _(digest.correct?('wrong-password')).must_equal false
  end

  it 'SECURITY: reconstructs digest object from serialized string' do
    digest = LockedCV::Password.digest('super-secret')
    restored = LockedCV::Password.from_digest(digest.to_s)

    _(restored.correct?('super-secret')).must_equal true
  end

  it 'SECURITY: rejects blank password for digesting' do
    _(
      proc { LockedCV::Password.digest('') }
    ).must_raise ArgumentError
  end

  it 'SECURITY: handles UTF-8 passwords (Chinese characters)' do
    digest = LockedCV::Password.digest('超級密碼123')

    _(digest.correct?('超級密碼123')).must_equal true
    _(digest.correct?('超級密碼124')).must_equal false
  end

  it 'SECURITY: digest differs from raw password text' do
    raw_password = 'my-secret-password'
    digest = LockedCV::Password.digest(raw_password)
    digest_string = digest.to_s

    _(digest_string).wont_include raw_password
    _(digest_string).must_be_kind_of String
  end

  it 'SECURITY: different passwords produce different digests' do
    digest_1 = LockedCV::Password.digest('password-one').to_s
    digest_2 = LockedCV::Password.digest('password-two').to_s

    _(digest_1).wont_equal digest_2
  end
end
