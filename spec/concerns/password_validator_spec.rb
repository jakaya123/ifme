# frozen_string_literal: true

describe PasswordValidator, type: :model do
  let(:user) { build(:user, password: nil) }

  describe '#password_validations' do
    context 'when password is blank' do
      it 'throws password error only from devise' do
        expect(user.valid?).to be false

        expect(user).to have(1).error_on(:password)
        expect(user.errors[:password]).not_to include(I18n.t('devise.registrations.password_errors.format'))
      end
    end

    context 'when Google auth is enabled' do
      let(:user) { build(:user_oauth) }

      it "doesn't throw any errors even if the password strength is weak" do
        user.password = 'warsdasdf'
        user.token = 'access token'
        expect(user.valid?).to be true
      end
    end

    context 'when password is valid' do
      it "doesn't throw any errors" do
        user.password = 'waspAr$0'
        expect(user.valid?).to be true
      end
    end

    context 'when password is invalid' do
      it 'returns respective error message' do
        ['waspar$0', 'waspaRs0', 'waspar$o', 'WASPAR$0', 'Was$0'].each do |password|
          user.password = password
          expect(user.valid?).to be false
          expect(user).to have(1).error_on(:password)
        end
      end
    end

    context 'previous three passwords' do
      it 'stores them in password_histories and forbids them as a new password' do
        password1 = 'Password@1'
        user.password = password1
        user.save
        expect(user.password_histories.count).to eq(1),
                                                 'Expected to create password history when user is created'

        expected_histories = 2
        passwords_2_3 = ['Password@2', 'Password@3']
        passwords_2_3.each_with_index do |password, index|
          user.password = password
          user.save
          expect(user.reload.password_histories.count).to eq(expected_histories + index),
                                                          'Expected to add to password history when password is changed'
        end

        password4 = 'Password@4'
        user.password = password4
        user.save
        expect(user.reload.password_histories.count).to eq(3),
                                                        'Expected to only preserve in history the three previous passwords'

        (passwords_2_3 + [password4]).each do |password|
          user.password = password
          saved = user.valid?
          expect(user.valid?).to be(false),
                                 'Expected user to be invalid if password is one of the previous three'
          expect(user.errors[:password]).to include(I18n.t('devise.registrations.password_errors.used'))
        end

        user.password = password1
        expect(user.valid?).to be(true),
                               'Expected user to be valid if password was used three or more passwords ago'

        new_password = 'Password@5'
        user.password = new_password
        expect(user.valid?).to be(true),
                               'Expected user to be valid if the password was not previously used'
      end
    end
  end

  context '#password_needs_update?' do
    # As the password_histories feature was not present initially, not all existing users will have password_histories.
    # Only users who were created after the addition of this feature will have password_histories.
    context 'without any histories' do
      before do
        allow_any_instance_of(User).to receive(:outdated_password?)
          .and_return(false)
      end

      it 'returns true when there are no password_histories' do
        allow(user).to receive(:password_histories).and_return([])
        expect(user.password_needs_update?).to be true
      end

      it 'returns false if there are any password_histories' do
        allow(user).to receive(:password_histories).and_return([PasswordHistory.new])
        expect(user.password_needs_update?).to be false
      end
    end

    context 'with Google auth user' do
      let(:user) { build(:user_oauth) }

      it 'returns false' do
        expect(user.password_needs_update?).to be false
      end
    end

    context 'with an outdated password' do
      before do
        user.password = 'Password@1'
        user.save
        allow_any_instance_of(User).to receive(:no_histories?)
          .and_return(false)
      end

      it 'returns true when password was updated more than 12 months ago' do
        allow_any_instance_of(PasswordHistory).to receive(:created_at)
          .and_return(
            Time.now.in_time_zone - (PasswordValidator::PASSWORD_VALIDITY_MONTHS.months + 10.minutes)
          )
        expect(user.password_needs_update?).to be true
      end

      it 'returns false when password was updated less than 12 months ago' do
        allow_any_instance_of(PasswordHistory).to receive(:created_at)
          .and_return(
            Time.now.in_time_zone - (PasswordValidator::PASSWORD_VALIDITY_MONTHS.months - 10.minutes)
          )
        expect(user.password_needs_update?).to be false
      end
    end
  end
end
