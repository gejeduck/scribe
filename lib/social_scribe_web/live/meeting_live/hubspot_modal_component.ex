defmodule SocialScribeWeb.MeetingLive.HubspotModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  alias SocialScribe.CrmProvider

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "hubspot-modal-wrapper" end)
    assigns = assign(assigns, :crm_label, CrmProvider.label_for(assigns.credential.provider))

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">Update in {@crm_label}</h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          Select a contact to see AI-suggested field updates extracted from the meeting transcript.
        </p>
      </div>

      <.contact_select
          selected_contact={@selected_contact}
          contacts={@contacts}
          loading={@searching}
          open={@dropdown_open}
          query={@query}
          target={@myself}
          error={@error}
        />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
          crm_label={@crm_label}
          meeting={@meeting}
          error={@error}
          field_errors={@field_errors}
          collapsed_fields={@collapsed_fields}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true
  attr :crm_label, :string, default: "CRM"
  attr :meeting, :map, default: nil
  attr :error, :string, default: nil
  attr :field_errors, :map, default: %{}
  attr :collapsed_fields, :any, default: MapSet.new()

  defp suggestions_section(assigns) do
    has_transcript = has_transcript_content?(assigns.meeting)
    assigns =
      assigns
      |> assign(:selected_count, Enum.count(assigns.suggestions, & &1.apply))
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="space-y-4">
      <%= if @loading do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Analyzing transcript with AI...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No CRM field updates suggested from transcript."
            submessage={if @has_transcript, do: "The AI didn't find any contact information (phone, email, company, etc.) mentioned in the meeting transcript.", else: "This meeting doesn't have a transcript yet. AI suggestions require a transcript."}
          />
        <% else %>
          <.inline_error :if={@error} message={@error} class="mb-4" />
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto pr-2">
              <.suggestion_card
                :for={suggestion <- @suggestions}
                suggestion={suggestion}
                field_error={Map.get(@field_errors, suggestion.field)}
                expanded={!MapSet.member?(@collapsed_fields, suggestion.field)}
                target={@myself}
              />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text={"Update #{@crm_label}"}
              submit_class="bg-green-600 hover:bg-green-700"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"1 object, #{@selected_count} fields in 1 integration selected to update"}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)
      |> assign_new(:step, fn -> :search end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:selected_contact, fn -> nil end)
      |> assign_new(:suggestions, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:field_errors, fn -> %{} end)
      |> assign_new(:collapsed_fields, fn -> MapSet.new() end)

    {:ok, socket}
  end

  defp validate_crm_fields(updates) do
    field_errors =
      updates
      |> Enum.reduce(%{}, fn
        {"email", value}, acc ->
          if valid_email?(value), do: acc, else: Map.put(acc, "email", "Invalid email address")

        {"phone", value}, acc ->
          if valid_phone?(value), do: acc, else: Map.put(acc, "phone", "Invalid phone number")

        {"mobilephone", value}, acc ->
          if valid_phone?(value), do: acc, else: Map.put(acc, "mobilephone", "Invalid phone number")

        {_field, _value}, acc ->
          acc
      end)

    if map_size(field_errors) > 0 do
      {:error, field_errors}
    else
      :ok
    end
  end

  defp valid_email?(""), do: true
  defp valid_email?(nil), do: true

  defp valid_email?(value) when is_binary(value) do
    value = String.trim(value)
    # Must have @ and domain with dot, no spaces
    value =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  end

  defp valid_phone?(""), do: true
  defp valid_phone?(nil), do: true

  defp valid_phone?(value) when is_binary(value) do
    value = String.trim(value)
    digit_count = value |> String.replace(~r/\D/, "") |> String.length()
    # At least 5 digits, and must not look like spoken email (e.g. "James at other")
    digit_count >= 5 and not String.contains?(String.downcase(value), " at ")
  end

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions}) when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {:hubspot_search, query, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
    end
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      # When opening dropdown with selected contact, search for similar contacts
      socket = assign(socket, dropdown_open: true, searching: true)
      query = "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"
      send(self(), {:hubspot_search, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      socket = assign(socket,
        loading: true,
        selected_contact: contact,
        error: nil,
        dropdown_open: false,
        query: "",
        suggestions: []
      )
      send(self(), {:generate_suggestions, contact, socket.assigns.meeting, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply,
     assign(socket,
       step: :search,
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       contacts: [],
       query: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_suggestion_details", %{"field" => field}, socket) do
    collapsed = socket.assigns.collapsed_fields
    new_collapsed =
      if MapSet.member?(collapsed, field) do
        MapSet.delete(collapsed, field)
      else
        MapSet.put(collapsed, field)
      end

    {:noreply, assign(socket, collapsed_fields: new_collapsed)}
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    checked_fields = Map.keys(applied_fields)

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            new_value -> %{suggestion | new_value: new_value}
          end

        %{suggestion | apply: apply?}
      end)

    # Clear validation errors when user edits
    {:noreply, assign(socket, suggestions: updated_suggestions, error: nil, field_errors: %{})}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, "") |> String.trim())
      end)

    case validate_crm_fields(updates) do
      :ok ->
        socket = assign(socket, loading: true, error: nil, field_errors: %{})
        send(self(), {:apply_hubspot_updates, updates, socket.assigns.selected_contact, socket.assigns.credential})
        {:noreply, socket}

      {:error, field_errors} ->
        {:noreply,
         assign(socket,
           loading: false,
           error: "Please fix the validation errors below.",
           field_errors: field_errors
         )}
    end
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end

  defp has_transcript_content?(nil), do: false

  defp has_transcript_content?(meeting) do
    transcript = Map.get(meeting, :meeting_transcript)
    content = transcript && Map.get(transcript, :content)
    data = content && Map.get(content, "data")
    is_list(data) and data != []
  end
end
