require 'spec_feature_helper'

describe 'editing the current user profile' do
  it 'updates the users profile' do
    sign_in
    manage_profile

    fill_in 'user_irc_nickname', with: 'eddardstark'
    fill_in 'user_company', with: 'Winterfell'
    fill_in 'user_jira_username', with: 'eddardstark'
    submit_form

    expect_to_see_success_message
  end
end
