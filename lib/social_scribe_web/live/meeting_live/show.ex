defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [crm_modal: 1]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.CrmApi
  alias SocialScribe.CrmProvider
  alias SocialScribe.CrmSuggestions

  @impl true
  def mount(%{"id" => meeting_id}, _session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      {:error, socket}
    else
      crm_credentials = Accounts.list_user_crm_credentials(socket.assigns.current_user.id)
      hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)
      salesforce_credential = Accounts.get_user_crm_credential(socket.assigns.current_user.id, "salesforce")

      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:crm_credentials, crm_credentials)
        |> assign(:salesforce_credential, salesforce_credential)
        |> assign(:crm_credential, nil)
        |> assign(:crm_provider, nil)
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => ""
          })
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"provider" => provider}, _uri, socket) do
    crm_credential = Accounts.get_user_crm_credential(socket.assigns.current_user.id, provider)

    socket =
      socket
      |> assign(:crm_credential, crm_credential)
      |> assign(:crm_provider, provider)

    {:noreply, socket}
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    socket =
      case socket.assigns[:live_action] do
        :hubspot ->
          if hubspot_credential = socket.assigns[:hubspot_credential] do
            socket
            |> assign(:crm_credential, hubspot_credential)
            |> assign(:crm_provider, "hubspot")
          else
            socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:crm_contact_search, query, credential}, socket) do
    case CrmApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
          id: "crm-modal",
          contacts: contacts,
          searching: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
          id: "crm-modal",
          error: "Failed to search contacts: #{inspect(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_crm_suggestions, contact, meeting, _credential}, socket) do
    case CrmSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = CrmSuggestions.merge_with_contact(suggestions, normalize_contact(contact))

        send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
          id: "crm-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
          id: "crm-modal",
          error: "Failed to generate suggestions: #{inspect(reason)}",
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:apply_crm_updates, updates, contact, credential}, socket) do
    contact_id = contact[:id] || contact["id"]

    case CrmApi.update_contact(credential, contact_id, updates) do
      {:ok, _updated_contact} ->
        socket =
          socket
          |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in CRM")
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.CrmModalComponent,
          id: "crm-modal",
          error: "Failed to update contact: #{inspect(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  defp normalize_contact(contact) do
    # Contact is already formatted with atom keys from HubspotApi.format_contact
    contact
  end

  attr :provider, :string, required: true
  attr :meeting, :map, required: true

  defp crm_update_button(assigns) do
    provider = assigns.provider
    label = CrmProvider.label_for(provider)
    patch = ~p"/dashboard/meetings/#{assigns.meeting}/crm/#{provider}"

    {button_class, icon} =
      case provider do
        "hubspot" ->
          {"inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-orange-500 hover:bg-orange-600 transition-colors",
           ~H"""
           <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
             <path d="M18.72 14.76c.35-.85.54-1.76.54-2.76 0-.72-.11-1.41-.3-2.05-.65.15-1.33.23-2.04.23A9.07 9.07 0 0112 9.9a8.963 8.963 0 01-4.92.28c-.2.64-.3 1.33-.3 2.05 0 1 .19 1.91.54 2.76 1.34-.5 2.75-.79 4.18-.79s2.84.29 4.22.79M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8m0-14c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3" />
           </svg>
           """}

        "salesforce" ->
          {"inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-[#00a1e0] hover:bg-[#0176d3] transition-colors",
           ~H"""
           <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
             <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z"/>
           </svg>
           """}

        _ ->
          {"inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 transition-colors",
           ~H"""
           <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
             <path d="M18.72 14.76c.35-.85.54-1.76.54-2.76 0-.72-.11-1.41-.3-2.05-.65.15-1.33.23-2.04.23A9.07 9.07 0 0112 9.9a8.963 8.963 0 01-4.92.28c-.2.64-.3 1.33-.3 2.05 0 1 .19 1.91.54 2.76 1.34-.5 2.75-.79 4.18-.79s2.84.29 4.22.79M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2m0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8m0-14c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3" />
           </svg>
           """}
      end

    assigns =
      assigns
      |> assign(:patch, patch)
      |> assign(:label, label)
      |> assign(:button_class, button_class)
      |> assign(:icon, icon)

    ~H"""
    <.link patch={@patch} class={@button_class}>
      {@icon}
      Update {@label} Contact
    </.link>
    """
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {segment["speaker"] || "Unknown Speaker"}:
              </span>
              {Enum.map_join(segment["words"] || [], " ", & &1["text"])}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
