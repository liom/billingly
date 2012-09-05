# A Customer is the main entity of Billingly:
#   * Customers are subscribed to plans
#   * Customers are charged for one-time expenses.
#   * Payments are received on a Customer's behalf and credited to their account.
#   * Invoices are generated periodically calculating charges a Customer incurred in.
#   * Receipts are sent to Customers when their invoices are paid.

require 'validates_email_format_of'

module Billingly
  class Customer < ActiveRecord::Base
    has_many :subscriptions
    has_many :one_time_charges
    has_many :invoices
    has_many :ledger_entries
    
    attr_accessible :email
    validates_email_format_of :email
    
    # Customers subscribe to the service and perform periodic payments to continue using it.
    # We offer common plans stating how much and how often they should pay, also, if the
    # payment is to be done at the beginning or end of the period (upfront or due-month)
    # Every customer can potentially get a special deal, but we offer common
    # deals as 'plans' from which a proper subscription is created.
    def subscribe_to_plan(plan) 
      subscriptions.last.terminate if subscriptions.last

      subscriptions.build.tap do |new|
        [:payable_upfront, :description, :periodicity, :amount].each do |k|
          new[k] = plan[k]
        end
        new.subscribed_on = Time.now
        new.save!
        new.generate_next_invoice  
      end
    end
    
    # Returns the actual subscription of the customer. while working with the 
    # customer API a customer should only have 1 active subscription at a time.
    def active_subscription
      subscriptions.last
    end 
    
    # Every transaction is registered in the journal from where a general ledger can
    # be retrieved.
    # Due to silly rounding errors on sqlite we need to convert decimals to float and then to
    # decimals again. :S
    def ledger
      Hash.new(0.0).tap do |all|
        ledger_entries.group_by(&:account).collect do |account, entries|
          values = entries.collect(&:amount).collect(&:to_f)
          all[account.to_sym] = values.inject(0.0) do |sum,item|
            (BigDecimal.new(sum.to_s) + BigDecimal.new(item.to_s)).to_f
          end
        end
      end
    end
    
    # Shortcut for adding ledger_entries for a particular customer.
    def add_to_ledger(amount, *accounts, extra)
      accounts = [] if accounts.nil?
      unless extra.is_a?(Hash)
        accounts << extra
        extra = {}
      end
      
      accounts.each do |account|
        ledger_entries.create!(extra.merge(amount: amount, account: account.to_s))
      end
    end
    
    # This class method is run periodically deactivate all customers who have overdue invoices.
    def self.deactivate_all_debtors
     # debugger
      
      debtors.where(deactivated_since: nil).all.each{|debtor| debtor.deactivate }
    end
    
    def self.debtors
       joins(:invoices).readonly(false)
        .where("#{Billingly::Invoice.table_name}.due_on < ?", Time.now)
        .where(billingly_invoices: {deleted_on: nil, receipt_id: nil})
    end

    # Credits a payment for a customer, settling invoices if possible.
    def credit_payment(amount)
      Billingly::Payment.credit_for(self, amount)
      Billingly::Invoice.charge_all(self.invoices)
      reactivate
    end
    
    def deactivate
      return if deactivated?
      active_subscription.terminate
      update_attribute(:deactivated_since, Time.now)
      return self
    end

    # Reactivates a customer that was deactivated when missed a previous payment.
    # The new subscription is parametrized the same as the old one. The old subscription
    # is terminated.
    def reactivate(new_plan = active_subscription)
      return unless deactivated?
      return if debtor?
      update_attribute(:deactivated_since, nil)
      subscribe_to_plan(new_plan)
      return self
    end
    
    def deactivated?
      not deactivated_since.nil?
    end
    
    def debtor?
      not self.class.debtors.find_by_id(self.id).nil?
    end
  end
end
