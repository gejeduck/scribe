defmodule SocialScribeWeb.UserSettingsLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.Bots
  alias SocialScribe.CrmProvider

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    google_accounts = Accounts.list_user_credentials(current_user, provider: "google")

    linkedin_accounts = Accounts.list_user_credentials(current_user, provider: "linkedin")

    facebook_accounts = Accounts.list_user_credentials(current_user, provider: "facebook")

    crm_providers =
      CrmProvider.known_providers()
      |> Enum.map(fn provider ->
        accounts = Accounts.list_user_credentials(current_user, provider: provider)
        %{provider: provider, label: CrmProvider.label_for(provider), accounts: accounts}
      end)

    user_bot_preference =
      Bots.get_user_bot_preference(current_user.id) || %Bots.UserBotPreference{}

    changeset = Bots.change_user_bot_preference(user_bot_preference)

    socket =
      socket
      |> assign(:page_title, "User Settings")
      |> assign(:google_accounts, google_accounts)
      |> assign(:linkedin_accounts, linkedin_accounts)
      |> assign(:facebook_accounts, facebook_accounts)
      |> assign(:crm_providers, crm_providers)
      |> assign(:user_bot_preference, user_bot_preference)
      |> assign(:user_bot_preference_form, to_form(changeset))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      :facebook_pages ->
        facebook_page_options =
          socket.assigns.current_user
          |> Accounts.list_linked_facebook_pages()
          |> Enum.map(&{&1.page_name, &1.id})

        socket =
          socket
          |> assign(:facebook_page_options, facebook_page_options)
          |> assign(:facebook_page_form, to_form(%{"facebook_page" => ""}))

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    changeset =
      socket.assigns.user_bot_preference
      |> Bots.change_user_bot_preference(params)

    {:noreply, assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("update_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    params = Map.put(params, "user_id", socket.assigns.current_user.id)

    case create_or_update_user_bot_preference(socket.assigns.user_bot_preference, params) do
      {:ok, bot_preference} ->
        {:noreply,
         socket
         |> assign(:user_bot_preference, bot_preference)
         |> put_flash(:info, "Bot preference updated successfully")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  @impl true
  def handle_event("disconnect_crm", %{"credential_id" => id}, socket) do
    credential = Accounts.get_user_credential!(id)

    if credential.user_id == socket.assigns.current_user.id do
      case Accounts.delete_user_credential(credential) do
        {:ok, _} ->
          crm_providers =
            CrmProvider.known_providers()
            |> Enum.map(fn provider ->
              accounts = Accounts.list_user_credentials(socket.assigns.current_user, provider: provider)
              %{provider: provider, label: CrmProvider.label_for(provider), accounts: accounts}
            end)

          {:noreply,
           socket
           |> assign(:crm_providers, crm_providers)
           |> put_flash(:info, "Account disconnected successfully")}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, "Failed to disconnect account")}
      end
    else
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    end
  end

  @impl true
  def handle_event("select_facebook_page", %{"facebook_page" => facebook_page}, socket) do
    facebook_page_credential = Accounts.get_facebook_page_credential!(facebook_page)

    case Accounts.update_facebook_page_credential(facebook_page_credential, %{selected: true}) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Facebook page selected successfully")
          |> push_navigate(to: ~p"/dashboard/settings")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    end
  end

  attr :provider, :string, required: true

  defp crm_provider_icon(assigns) do
    ~H"""
    <span class="-ml-1 mr-3 h-5 w-5 inline-block" aria-hidden="true">
      <%= case @provider do %>
        <% "hubspot" -> %>
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
            <path d="M18.164 7.93V5.084a2.198 2.198 0 001.267-1.984v-.066A2.2 2.2 0 0017.231.834h-.066a2.2 2.2 0 00-2.2 2.2v.066c0 .873.517 1.626 1.267 1.984V7.93a6.152 6.152 0 00-3.267 1.643l-6.6-5.133a2.726 2.726 0 00.067-.582A2.726 2.726 0 003.706 1.13a2.726 2.726 0 00-2.726 2.727 2.726 2.726 0 002.726 2.727c.483 0 .938-.126 1.333-.347l6.486 5.047a6.195 6.195 0 00-.556 2.572 6.18 6.18 0 00.56 2.572l-1.57 1.223a2.457 2.457 0 00-1.49-.504 2.468 2.468 0 00-2.468 2.468 2.468 2.468 0 002.468 2.468 2.468 2.468 0 002.468-2.468c0-.29-.05-.568-.142-.826l1.558-1.213a6.2 6.2 0 003.812 1.312 6.2 6.2 0 006.199-6.2 6.2 6.2 0 00-4.2-5.856zm-4.2 9.193a3.337 3.337 0 110-6.674 3.337 3.337 0 010 6.674z"/>
          </svg>
        <% "salesforce" -> %>
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z"/>
          </svg>
        <% _ -> %>
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
            <path fill-rule="evenodd" d="M6 2a2 2 0 00-2 2v12a2 2 0 002 2h8a2 2 0 002-2V4a2 2 0 00-2-2H6zm1 2h6v2H7V4zm0 4h6v2H7V8zm0 4h6v2H7v-2z" clip-rule="evenodd"/>
          </svg>
      <% end %>
    </span>
    """
  end

  defp create_or_update_user_bot_preference(bot_preference, params) do
    case bot_preference do
      %Bots.UserBotPreference{id: nil} ->
        Bots.create_user_bot_preference(params)

      bot_preference ->
        Bots.update_user_bot_preference(bot_preference, params)
    end
  end
end
