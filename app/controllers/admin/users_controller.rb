class Admin::UsersController < ApplicationController
  before_action :set_user, only: [:edit, :update, :destroy, :login, :show, :verify]
  authorize_resource

  def index
    @users = User.search(params, admin_users_path)
    flash.now[:warning] = t("no_matches") if @users.count == 0
    save_last_search(@users, :users)
  end

  def new
    @player = Player.find(params[:player_id]) # always invoked from a player
    @user = User.new(player_id: @player.id)
  end

  def create
    @user = User.new(user_params(:new))
    @user.status = "OK"
    @user.verified_at = DateTime.now

    if @user.save
      @user.journal(:create, current_user, request.remote_ip)
      redirect_to [:admin, @user], notice: "User was successfully created"
    else
      @player = Player.find(@user.player_id)
      render action: "new"
    end
  end

  def show
    @prev_next = Util::PrevNext.new(session, User, params[:id], admin: true)
    @entries = @user.journal_search if can?(:create, User)
  end

  def update
    if @user.update(user_params)
      @user.journal(:update, current_user, request.remote_ip)
      redirect_to [:admin, @user], notice: "User was successfully updated"
    else
      render action: "edit"
    end
  end

  def destroy
    email = @user.email
    if reason = @user.reason_to_not_delete
      redirect_to admin_user_path(@user), alert: "Can't delete #{email} because this user #{reason}"
    else
      @user.journal(:destroy, current_user, request.remote_ip)
      @user.destroy
      redirect_to admin_users_path, notice: "User #{email} was successfully deleted"
    end
  end

  def login
    if !current_user.admin?
      redirect_to admin_user_path(@user), alert: "Only administrators can switch user"
    elsif @user.id == current_user.id
      redirect_to admin_user_path(@user), alert: "Can't switch to the current user"
    elsif @user.admin?
      redirect_to admin_user_path(@user), alert: "Can't switch to another administrator"
    else
      session[:user_id] = @user.id
      redirect_to home_path, notice: "#{t('session.signed_in_as')} #{@user.email}"
    end
  end

  def verify
    if @user.verified?
      redirect_to admin_user_path(@user), alert: "User is already verified"
      return
    end
    @user.update(verified_at: Time.now)
    @user.journal(:update, current_user, request.remote_ip)
    redirect_to admin_user_path(@user), notice: "User was successfully verified"
  end

  private

  def set_user
    @user = User.include_player.find(params[:id])
    @player = @user.player
  end

  def user_params(new_record=false)
    extra = new_record ? [:email, :player_id] : [:status, :verify]
    params.require(:user).permit(*extra, :expires_on, :password, :disallow_reporting, roles: [])
  end
end
