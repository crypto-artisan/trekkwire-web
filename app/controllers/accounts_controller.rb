class AccountsController < Accounts::BaseController
  before_action :authenticate_user!
  before_action :set_account, only: [:show, :edit, :update, :destroy, :switch, :delete_photo_attachment]
  before_action :require_account_admin, only: [:edit, :update, :destroy]
  before_action :prevent_personal_account_deletion, only: [:destroy]

  # GET /accounts
  def index
    @pagy, @accounts = pagy(current_user.accounts)
  end

  # GET /accounts/1
  def show
    unless Rails.env.test? || @account.customer_type == "traveler"
      @stripe_setup_link = @account.stripe_setup_link(request.base_url)
    end
  end

  # GET /accounts/new
  def new
    @account = Account.new
  end

  # GET /accounts/1/edit
  def edit
    @operating_location = @account.operating_location || @account.build_operating_location
  end

  # POST /accounts
  def create
    @account = Account.new(account_params.merge(owner: current_user))
    @account.account_users.new(user: current_user, admin: true)

    if @account.save
      # Add any after-create functionality here
      # ActsAsTenant.with_tenant(@account) do
      #   # Create default records here...
      # end

      # Fetch requests / pushState doesn't work between (sub)domains
      # so we'll just link to switch to the new account in the notice instead
      if request.format == :turbo_stream && Jumpstart::Multitenancy.subdomain? && @account.subdomain?
        redirect_to @account, notice: t(".created_and_switch_html", link: root_url(subdomain: @account.subdomain))

      else
        # Automatically switch to the new account on the next request
        flash[:notice] = t(".created")
        switch
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /accounts/1
  def update
    if @account.update(account_params)
      redirect_to @account, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /accounts/1
  def destroy
    @account.destroy
    redirect_to accounts_url, status: :see_other, notice: t(".destroyed")
  end

  def public_profile
    @account = Account.find_by(id: params[:account_id])
  end

  # Current account will not change until the next request
  def switch
    # Uncomment this if you would like to redirect to the custom domain when switching accounts.
    # This is not enabled by default because we can't guarantee the domain is configured properly.
    #
    # if Jumpstart::Multitenancy.domain? && @account.domain?
    #  redirect_to @account.domain, allow_other_host: true

    if Jumpstart::Multitenancy.subdomain? && @account.subdomain?
      redirect_to root_url(subdomain: @account.subdomain), allow_other_host: true

    elsif Jumpstart::Multitenancy.path?
      redirect_to root_url(script_name: "/#{@account.id}")

    else
      session[:account_id] = @account.id
      redirect_to root_path
    end
  end

  def delete_photo_attachment
    params[:photos].each do |photo|
      @account.photos.find(photo).purge
    end
    redirect_to edit_account_path(@account), notice: "Photo deleted"
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_account
    @account = current_user.accounts.find(params[:id])
  end

  # Only allow a trusted parameter "white list" through.
  def account_params
    attributes = [:name, :customer_type, :description, :tagline, :avatar, :active, :linkedin_social, :facebook_social, :x_social, :youtube_social, :instagram_social, :available_now, photos: [], language_ids: [], activity_ids: [], :operating_location_attributes => [:id, :address, :latitude, :longitude]]
    attributes << :domain if Jumpstart::Multitenancy.domain?
    attributes << :subdomain if Jumpstart::Multitenancy.subdomain?
    params.require(:account).permit(*attributes)
  end

  def prevent_personal_account_deletion
    if @account.personal?
      redirect_to account_path(@account), alert: t(".personal.cannot_delete")
    end
  end
end
