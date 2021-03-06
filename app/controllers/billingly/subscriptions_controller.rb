# This controller takes care of managing subscriptions.
class Billingly::SubscriptionsController < ::ApplicationController
  before_filter :requires_customer
  before_filter :requires_active_customer, except: [:index, :reactivate]

  # Index shows the current subscription to customers while they are active.
  # It's also the page that prompts them to reactivate their account when deactivated.
  # It's likely the only reachable page for deactivated customers.
  def index
    @subscription = current_customer.active_subscription
    @plans = Billingly::Plan.all
    @invoices = current_customer.invoices.order('created_at DESC')
  end
  
  # Subscribe the customer to a plan, or change his current plan.
  def create
    plan = Billingly::Plan.find(params[:plan_id])
    unless current_customer.can_subscribe_to?(plan)
      return redirect_to subscriptions_path, notice: 'Cannot subscribe to that plan'
    end
    current_customer.subscribe_to_plan(plan)
    on_subscription_success
  end

  # Action to reactivate an account for a customer that left voluntarily and does
  # not owe any money to us.
  # Their account will be reactivated to their old subscription plan immediately.
  # They can change plans afterwards.
  def reactivate
    plan = Billingly::Plan.find_by_id(params[:plan_id])
    if current_customer.reactivate(plan).nil?
      return render nothing: true, status: 403
    end
    on_reactivation_success
  end
  
  # Unsubscribes the customer from his last subscription and deactivates his account.
  # Performing this action would set the deactivation reason to be 'left_voluntarily'
  def deactivate
    current_customer.deactivate_left_voluntarily
    redirect_to(action: :index)
  end

  # When a subscription is sucessful this callback is triggered.
  # Host applications should override it by subclassing this subscriptionscontroller,
  # and include their own behaviour, and for example grant the privileges associated
  # to the subscription plan.
  def on_subscription_success
    redirect_to(action: :index) 
  end
  
  def on_reactivation_success
    redirect_to(action: :index) 
  end
end
