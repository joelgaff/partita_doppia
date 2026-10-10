require "test_helper"

# For driving the app in a simulator, development can pin the sign-in code
# with DEV_LOGIN_CODE. Nowhere else honours it, and the code still expires.
class DevelopmentLoginCodeTest < ActiveSupport::TestCase
  setup do
    @org  = organizations(:one)
    @user = @org.users.create!(name: "Joel", email_address: "joel@example.com")
  end

  test "a code can be issued as given, and works like any other" do
    code = @user.issue_login_code!(code: "123456")
    assert_equal "123456", code
    assert @user.login_code_valid?("123456")
    assert_not @user.login_code_valid?("654321")
  end

  test "the development code is only read in development" do
    ENV["DEV_LOGIN_CODE"] = "123456"
    assert_nil Auth.development_login_code, "not in the test environment"
    stub_method(Rails.env, :development?, -> { true }) do
      assert_equal "123456", Auth.development_login_code
      ENV.delete("DEV_LOGIN_CODE")
      assert_nil Auth.development_login_code
    end
  ensure
    ENV.delete("DEV_LOGIN_CODE")
  end
end
