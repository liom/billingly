require 'spec_helper'

describe Billingly::SubscriptionsController do
  let(:customer){ create :customer }

  describe 'when allowing/denying access' do
    it 'index requires a customer' do
      controller.stub current_customer: nil
      get :index
      response.should redirect_to(root_path)
    end

    it 'index does not require customer to be active' do
      controller.stub current_customer: create(:first_year, :deactivated, :overdue).customer
      get :index
      response.should_not be_redirect
    end
  end
  
  it 'has a callback for successful subscription creation' do
    controller.should_receive(:redirect_to).with action: :index
    controller.on_subscription_success
  end

  describe 'when customer logged in' do
    before(:each) do
      controller.stub current_customer: customer
    end

    it 'shows the current customer subscription details' do
      subscription = create(:first_year, customer: customer)
      get :index
      assigns(:subscription).should_not be_nil
    end

    it 'subscribes a customer to a plan' do
      plan = create :pro_50_monthly
      customer.should_receive(:subscribe_to_plan).with(plan)
      controller.should_receive :on_subscription_success
      post :create, plan_id: plan.id
    end
    
    it 'does not let customer subscribe to a plan if they cant subscribe to it' do
      plan = create :pro_50_monthly
      customer.stub(can_subscribe_to?: false)
      post :create, plan_id: plan.id
      response.should redirect_to(subscriptions_path)
      flash[:notice].should =~ /Cannot subscribe to that plan/ 
    end

    it 'does not subscribe a customer to a bogus plan' do
      customer.should_not_receive(:subscribe_to_plan)
      controller.should_not_receive :on_subscription_success
      expect do
        post :create, plan_id: 'blah'
      end.to raise_exception ActiveRecord::RecordNotFound
    end
  
    it 'should set the diactivation reason to be left_voluntarily when deactivating' do
      customer.should_receive(:deactivate_left_voluntarily)
      post :deactivate
      response.should redirect_to(action: :index)
    end
  end
  
  describe 'when reactivating an inactive account' do
    let :deactivated do
      customer = create(:first_year, customer: create(:deactivated_customer)).customer
      controller.stub current_customer: customer
      customer
    end

    it 'reactivates a customer who left in their own terms' do
      deactivated.should_receive(:reactivate).and_return(deactivated)
      post :reactivate
      response.should redirect_to(action: :index)
    end

    it 'calls the on_reactivation_success callback when reactivating' do
      deactivated
      controller.should_receive(:on_reactivation_success).and_raise('Redirected')
      expect{ post :reactivate}.to raise_exception('Redirected')
    end

    it 'Fails when reactivation fails' do
      deactivated.stub(reactivate: nil)
      post :reactivate
      response.status.should == 403
    end
    
    it 'Optionally takes a plan when reactivating' do
      customer = deactivated
      plan = create(:pro_50_monthly)
      deactivated.should_receive(:reactivate).with(plan).and_return(deactivated)
      post :reactivate, plan_id: plan.id.to_s
      response.should redirect_to(action: :index)
    end
  end
end

