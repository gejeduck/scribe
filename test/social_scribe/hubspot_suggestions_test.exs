defmodule SocialScribe.HubspotSuggestionsTest do
  use SocialScribe.DataCase

  import Mox

  alias SocialScribe.HubspotSuggestions

  setup :verify_on_exit!

  describe "generate_suggestions_from_meeting/1" do
    test "maps AI suggestions to expected format with field labels" do
      meeting = %{id: 1, title: "Test Meeting"}

      ai_suggestions = [
        %{field: "phone", value: "555-1234", context: "Mentioned in call"},
        %{field: "company", value: "Acme Corp", context: "Works at Acme"},
        %{field: "jobtitle", value: "Engineer", context: "Job title mentioned"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn ^meeting ->
        {:ok, ai_suggestions}
      end)

      assert {:ok, suggestions} = HubspotSuggestions.generate_suggestions_from_meeting(meeting)

      assert length(suggestions) == 3

      phone = Enum.find(suggestions, &(&1.field == "phone"))
      assert phone.label == "Phone"
      assert phone.new_value == "555-1234"
      assert phone.current_value == nil
      assert phone.context == "Mentioned in call"
      assert phone.apply == true
      assert phone.has_change == true

      company = Enum.find(suggestions, &(&1.field == "company"))
      assert company.label == "Company"
      assert company.new_value == "Acme Corp"

      jobtitle = Enum.find(suggestions, &(&1.field == "jobtitle"))
      assert jobtitle.label == "Job Title"
    end

    test "returns error when AI content generator fails" do
      meeting = %{id: 1}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _meeting ->
        {:error, :rate_limited}
      end)

      assert {:error, :rate_limited} = HubspotSuggestions.generate_suggestions_from_meeting(meeting)
    end

    test "preserves optional context and timestamp from AI response" do
      meeting = %{id: 1}
      ai_suggestions = [
        %{field: "email", value: "test@example.com", context: "From transcript", timestamp: "0:45"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _ -> {:ok, ai_suggestions} end)

      assert {:ok, [suggestion]} = HubspotSuggestions.generate_suggestions_from_meeting(meeting)
      assert suggestion.context == "From transcript"
      assert suggestion.timestamp == "0:45"
    end

    test "uses field name as label when not in known field_labels" do
      meeting = %{id: 1}
      ai_suggestions = [%{field: "custom_field", value: "value", context: nil}]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_hubspot_suggestions, fn _ -> {:ok, ai_suggestions} end)

      assert {:ok, [suggestion]} = HubspotSuggestions.generate_suggestions_from_meeting(meeting)
      assert suggestion.label == "custom_field"
    end
  end

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "company",
          label: "Company",
          current_value: nil,
          new_value: "Acme Corp",
          context: "Works at Acme",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        phone: nil,
        company: "Acme Corp",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since company already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "123",
        email: "test@example.com"
      }

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "123", email: "test@example.com"}

      result = HubspotSuggestions.merge_with_contact([], contact)

      assert result == []
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "123", phone: nil}

      result = HubspotSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end
  end
end
