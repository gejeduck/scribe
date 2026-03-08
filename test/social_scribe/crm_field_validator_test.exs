defmodule SocialScribe.CrmFieldValidatorTest do
  use SocialScribe.DataCase

  alias SocialScribe.CrmFieldValidator

  describe "validate/1" do
    test "returns :ok for valid email and phone" do
      assert CrmFieldValidator.validate(%{"email" => "user@example.com", "phone" => "555-1234"}) == :ok
    end

    test "returns :ok for empty or nil values" do
      assert CrmFieldValidator.validate(%{"email" => "", "phone" => nil}) == :ok
    end

    test "returns error for invalid email" do
      assert {:error, %{"email" => "Invalid email address"}} =
               CrmFieldValidator.validate(%{"email" => "bad-email"})
    end

    test "returns error for invalid phone (too few digits)" do
      assert {:error, %{"phone" => "Invalid phone number"}} =
               CrmFieldValidator.validate(%{"phone" => "123"})
    end

    test "returns error for invalid mobilephone" do
      assert {:error, %{"mobilephone" => "Invalid phone number"}} =
               CrmFieldValidator.validate(%{"mobilephone" => "123"})
    end

    test "returns error for phone containing ' at ' (spoken email)" do
      assert {:error, %{"phone" => "Invalid phone number"}} =
               CrmFieldValidator.validate(%{"phone" => "555 at 1234"})
    end

    test "passes non-validated fields through" do
      assert CrmFieldValidator.validate(%{"company" => "Acme", "jobtitle" => "Engineer"}) == :ok
    end

    test "accumulates multiple validation errors" do
      assert {:error, errors} =
               CrmFieldValidator.validate(%{"email" => "bad", "phone" => "12"})

      assert Map.has_key?(errors, "email")
      assert Map.has_key?(errors, "phone")
    end
  end
end
