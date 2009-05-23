require File.dirname(__FILE__) + '/../test_helper'

require 'date'

module Factory
  def self.create_labor(attributes = {}, activity_attributes = {})
    employee = Employee.find(
      :first, 
      :conditions => ['credentials.email_address = ? ', 'chris@derosetechnologies.com'], 
      :include => [:credential]
    )
    employee ||= self.create_employee

    l = Activity::Labor.new(
      { 
      :employee => employee,
      :comments => 'Performed productivity enhancing work.',
      :duration => 60
      }.merge(attributes) 
    )

    assign_sub_activity l, activity_attributes

    raise StandardError unless l.save!
    
    l    
  end
  
  def self.create_material(attributes = {}, activity_attributes = {})
    m = Activity::Material.new(
      {
      :label => 'Expensive Widget',
      :comments => 'Brand-new straight from the factory.'
      }.merge(attributes) 
    )

    assign_sub_activity m, {:cost => 849.99, :tax => 51.00 }.merge(activity_attributes)

    raise StandardError unless m.save!
    
    m
  end
  
  def self.create_proposal(attributes = {}, activity_attributes = {})
    p = Activity::Proposal.new(
      {
      :label => 'Driveway Repavement',
      :comments => 'Includes top quality asphault...',
      :proposed_on => (DateTime.now << 1) # one month ago ...
      }.merge(attributes) 
    )

    assign_sub_activity p, {:cost => 1200.0, :tax => 20.01 }.merge(activity_attributes)

    raise StandardError unless p.save!
    
    p
  end
  
  def self.create_adjustment(attributes = {}, activity_attributes = {})
    a = Activity::Adjustment.new(
      {
      :label => 'Starting Balance',
      :comments => 'Before we moved to the amazing Brisk Bills!'
      }.merge(attributes) 
    )

    assign_sub_activity a, {:cost => 300.0, :tax => 0 }.merge(activity_attributes)

    raise StandardError unless a.save!
    
    a
  end
  
  def self.create_client(attributes = {})
    company_name = (attributes.has_key?(:company_name)) ? attributes[:company_name] : 'ACME Fireworks'
    
    client = Client.find :first, :conditions => ['company_name = ?', company_name]
    
    (client) ? client : Client.create!(
      {
      :company_name => 'ACME Fireworks',
      :address1     => '470 S. Andrews Ave.',
      :address2     => 'Suite 206', 
      :phone_number => '954-942-7703',
      :fax_number   => '954-942-7933' 
      }.merge(attributes)
    )
  end
  
  def self.create_employee(attributes = {})
    Employee.create!( 
      {
      :first_name      => 'Chris',
      :last_name       => 'DeRose',
      :email_address   => 'chris@derosetechnologies.com',
      :phone_extension => 69
      }.merge(attributes)
    )
  end
  
  def self.generate_invoice(total, attributes = {})
    client = Factory.create_client
    
    attributes[:issued_on] ||= Time.now
    
    activity_increments = (total.floor).to_f/10
    
    1.upto(10) do |i|
      activity_amount = activity_increments
      activity_amount += total - total.floor if i == 1 

      a = Activity::Adjustment.new :label => 'test invoice'
      a.activity.cost = activity_amount
      a.activity.client = client
      a.activity.occurred_on = (attributes[:issued_on] - 1.months)
      a.activity.is_published = true
      a.save!
    end

    Invoice.create!( { :client => client }.merge(attributes) )
  end

  private
  
  def self.assign_sub_activity( model , passed_attributes)

    attributes = {} 
    attributes[:is_published] = true     unless passed_attributes.has_key? :is_published
    attributes[:occurred_on]  = DateTime.now unless passed_attributes.has_key? :occurred_on
    
    unless passed_attributes.has_key? :client or passed_attributes.has_key? :client_id
      attributes[:client] = Client.find :first, :conditions => ['company_name = ?', 'ACME Fireworks']
      attributes[:client] ||= self.create_client
    end

    model.activity.attributes = attributes.merge(passed_attributes) 
  end

end


class InvoiceTest < ActiveSupport::TestCase

  fixtures :activity_types

  def setup
    @activity_types = ActivityType.find :all
  end

  def test_only_newest_invoice_can_be_unpublished
    client = Factory.create_client
    
    # Once they're published they cant be unpublished unless they're the newest invoice...
    invoices = [
      Factory.generate_invoice(100.00, :issued_on => (DateTime.now << 4), :is_published => true ),
      Factory.generate_invoice(200.00, :issued_on => (DateTime.now << 3), :is_published => true ),
      Factory.generate_invoice(300.00, :issued_on => (DateTime.now << 2), :is_published => true ),
      Factory.generate_invoice(400.00, :issued_on => (DateTime.now << 1), :is_published => true )
    ]

    invoices[0...2].each do |inv|
      assert_raise(ActiveRecord::RecordInvalid) {set_published inv, false}
    end

    assert_nothing_raised { set_published invoices[3], false }
    
  end

  def test_ensure_client_cant_be_changed
    client = Factory.create_client
    client2 = Factory.create_client :company_name => 'Client 2, Inc.'
    
    invoice = Factory.generate_invoice 100.00, :client => client
    
    assert_raise(ActiveRecord::RecordInvalid) do 
      invoice.client = client2
      invoice.save!
    end
  end

  def test_is_published_behavior
    client = Factory.create_client

    Payment.create!(
      :client => client,
      :payment_method_id => 1,
      :amount => BigDecimal.new(2000.00.to_s),
      :paid_on => (DateTime.now << 1)
    ) 

    inv = Factory.generate_invoice 1000.00, :issued_on => (DateTime.now >> 12)
    
    # Change payment, save:
    assert_nothing_raised do
      inv.comments = 'This should be editable'
      inv.save!
    end
    
    # Now we Mark it published
    assert_nothing_raised do
      inv.is_published = true
      inv.save!
    end
    
    # Now make sure we raise something on edit
    assert_raise( ActiveRecord::RecordInvalid ) do
      inv.comments = 'This shouldnt actually work'
      inv.save!
    end

    # Now we Mark it unpublished
    assert_nothing_raised do
      inv.is_published = false
      inv.save!
    end

    # Change payment again, save:
    assert_nothing_raised do
      inv.comments = 'This time it should work'
      inv.save!
    end

  end

  def test_invoice_create_defaults
    inv = Invoice.create

    assert_equal Time.utc(*Time.now.to_a).last_month.end_of_month, inv.issued_on
    assert_equal false, inv.is_published
  end

  def test_errors
    client = Factory.create_client
    
    # Make sure we cant create an invoice with no client :
    assert_raise(ActiveRecord::RecordInvalid) { Invoice.create! :client => nil, :issued_on => DateTime.now }

    # Make sure we can't edit the client once an invoice is created (for now ... that might change)
    invoice = nil
    assert_nothing_raised { invoice = Invoice.create! :client => client, :issued_on => DateTime.now }
    
    invoice.client = Factory.create_client :company_name => 'PBR Inc.'
    
    assert_raise(ActiveRecord::RecordInvalid) { invoice.save! }
  end
  
  def test_activity_assignment_on_create_delete
    invoice = nil
  
    client = Factory.create_client
        
    # These are a ruse.. make sure these dont get added:
    Factory.create_labor( {}, {:occurred_on => (DateTime.now >> 1)} ) # This is newer then issued_on
    Factory.create_labor( {}, {:client_id => 6969} )                  # This is a different client
    Factory.create_labor( {}, {:is_published => false} )              # This isnt published yet
    
    # These will be legit:
    valid_activities = [
      Factory.create_labor.activity.id,
      Factory.create_material.activity.id,
      Factory.create_proposal.activity.id,
      Factory.create_adjustment.activity.id
    ]

    assert_nothing_raised { invoice = Invoice.create! :client => client, :issued_on => (DateTime.now+1), :activity_types => @activity_types }
    
    # Make sure the right activities were included:
    assert_equal 4, invoice.activities.length
    invoice.activities.each { |a| assert_equal true, valid_activities.include?(a.id) }
    
    # Make sure the cost adds up:
    assert_equal 2421.0.to_s, invoice.amount.to_s
    
    assert_equal 2421.0.to_s, (invoice.sub_total+invoice.taxes_total).to_s
    
    # Now Make sure we unassign on a delete:
    assert_nothing_raised { invoice.destroy }
    
    valid_activities.each { |a_id| assert_equal nil, Activity.find(a_id).invoice_id }
  end

  def test_uneditable_upon_is_published

    client = Factory.create_client

    labor = Factory.create_labor
    material = Factory.create_material
    proposal = Factory.create_proposal
    adjustment = Factory.create_adjustment
    
    invoice = nil
    
    assert_nothing_raised do
      invoice = Invoice.create!(
        :client => client, 
        :issued_on => DateTime.now,
        :activity_types => @activity_types 
      )

      invoice.is_published = true
      invoice.save!
    end    
    
    # Make sure they can't destroy:
    assert_equal false, invoice.destroy
    
    # Make sure they can't update:
    invoice.comments = "This shouldn't be retained!"
    assert_raise(ActiveRecord::RecordInvalid) { invoice.save! }

    # Make sure the right activities were included:
    assert_equal 4, invoice.activities(true).size
    
    # Now make sure we can't adjust any of them:
    invoice.activities.each do |a|
      # Make sure they can't destroy:
      assert_equal false, a.destroy

      # Make sure they can't update:
      a.cost = 69.0
      assert_raise(ActiveRecord::RecordInvalid) { a.save! }

      # Make sure we can't adjust/destroy the subtype either
      a_st = a.send(a.activity_type)
      
      # Make sure they can't destroy:
      assert_equal false, a_st.destroy
      
      # Make sure they can't update:
      a_st.comments = "THis Shouldn't get committed...."
      assert_raise(ActiveRecord::RecordInvalid) { a_st.save! }
    end
        
  end
  
  def test_issued_date_updates
    # This make sure the activity adjustments are working the way they should be

    client = Factory.create_client # This needs to get done here so the factory attaches the activities to it...

    present_date = DateTime.now
    past_date    = (present_date << 1)
    future_date  = (present_date >> 1)
    
    past_activities = [
      Factory.create_labor({}, {:occurred_on => past_date}).activity.id,
      Factory.create_material({}, {:occurred_on => past_date}).activity.id,
      Factory.create_proposal({}, {:occurred_on => past_date}).activity.id,
      Factory.create_adjustment({}, {:occurred_on => past_date}).activity.id
    ]
    
    future_activities = [
      Factory.create_labor({}, {:occurred_on => future_date}).activity.id,
      Factory.create_material({}, {:occurred_on => future_date}).activity.id,
      Factory.create_proposal({}, {:occurred_on => future_date}).activity.id,
      Factory.create_adjustment({}, {:occurred_on => future_date}).activity.id
    ]
    
    invoice = nil
    assert_nothing_raised { invoice = Invoice.create! :client => client, :issued_on => present_date, :activity_types => @activity_types  }
    
    # Make sure the right activities were included:
    assert_equal 4, invoice.activities(true).size
    
    invoice.activities.each do |a| 
      assert_equal true,  past_activities.include?(a.id) 
      assert_equal false, future_activities.include?(a.id)
    end
    
    # Now let's set to the way future:
    assert_nothing_raised do
      invoice.issued_on = present_date >> 2
      invoice.save!
    end
    
    # Make sure everything ends up in there:
    assert_equal 8, invoice.activities(true).size
    
    invoice.activities(true).each do |a| 
      assert_equal true, (past_activities.include?(a.id) or future_activities.include?(a.id) )
    end
    
    # Now let's set back to present:
    assert_nothing_raised do
      invoice.issued_on = present_date
      invoice.save!
    end
    
    # Make sure we're where we should be:
    assert_equal 4, invoice.activities(true).size
    
    invoice.activities.each do |a| 
      assert_equal true,  past_activities.include?(a.id) 
      assert_equal false, future_activities.include?(a.id)
    end
    
  end

  def test_invoice_deletes_only_if_recent    
    invoice_time = Time.new
    
    invoices = [20,40,80,160,320,640,1280].collect do |amt| 
      invoice_time += 1.weeks
      Factory.generate_invoice amt, :issued_on => invoice_time
    end

    while invoices.length > 0
      0.upto(invoices.length-2)  { |i| assert_equal false, invoices[i].destroy }
    
      assert_not_equal false, invoices.delete_at(invoices.length-1).destroy
    end
    
  end
  
  def test_activity_type_inclusions
    client = Factory.create_client
    
    @activity_types = ActivityType.find :all
    
    a_type_map = HashWithIndifferentAccess.new
    @activity_types.each{|at| a_type_map[at.label.downcase] = at }
    
    # First, let's Make sure this includion feature actually works during a create
    present_date = DateTime.now
    past_date    = (present_date << 1)
    
    activities = [
      Factory.create_labor({}, {:occurred_on => past_date, :cost => 1.99 }),
      Factory.create_labor({}, {:occurred_on => past_date, :cost => 1.99 }),
      Factory.create_material({}, {:occurred_on => past_date}),
      Factory.create_material({}, {:occurred_on => past_date}),
      Factory.create_proposal({}, {:occurred_on => past_date}),
      Factory.create_proposal({}, {:occurred_on => past_date}),
      Factory.create_adjustment({}, {:occurred_on => past_date}),
      Factory.create_adjustment({}, {:occurred_on => past_date})
    ]
    
    invoice = nil
    
    assert_nothing_raised do 
      invoice = Invoice.create!(
        :client => client, 
        :issued_on => present_date, 
        :activity_types => [ a_type_map[:material], a_type_map[:labor] ]
      )
    end

    assert_equal 1805.96.to_s, invoice.amount.to_s

    assert_equal 1805.96.to_s, (invoice.sub_total+invoice.taxes_total).to_s

    assert_equal(
      invoice.activity_ids, 
      activities.select{|a| /^Activity::(Material|Labor)$/.match a.class.to_s}.collect{|a| a.activity.id}
    )
    
    # Let's remove a type and see if this works the way it should:
    assert_nothing_raised do
      invoice.activity_types.delete a_type_map[:material]
      invoice.save!
      
      # We have to expire the cache here....
      invoice.activities(true)
    end

    assert_equal 3.98.to_s, invoice.amount.to_s
    
    assert_equal 3.98.to_s, (invoice.sub_total+invoice.taxes_total).to_s
    
    assert_equal(
      activities.select{|a| /^Activity::Labor$/.match a.class.to_s}.collect{|a| a.activity.id},
      invoice.activity_ids
    )

    # Now let's add the rest of the types, and see if it works the way it should:
    assert_nothing_raised do
      invoice.activity_types.push a_type_map[:material], a_type_map[:proposal]
      invoice.save!
      
      # We have to expire the cache here....
      invoice.activities(true)
    end

    assert_equal 4245.98.to_s, invoice.amount.to_s
    
    assert_equal 4245.98.to_s, (invoice.sub_total+invoice.taxes_total).to_s
    
    assert_equal(
      activities.select{|a| /^Activity::(Material|Labor|Proposal)$/.match a.class.to_s}.collect{|a| a.activity.id},
      invoice.activity_ids
    )
        
    # Make sure we can't add/remove activity types for a published invoice
    assert_nothing_raised{ set_published invoice, true }
    
    assert_raise(RuntimeError) { invoice.activity_types.push a_type_map[:adjustment]}

    assert_raise(RuntimeError) { invoice.activity_types.delete a_type_map[:material]}
  end
  
  def test_empty_invoice
    # Create an invoice with no activities - even though it should have a balance of zero, also make sure things dont puke
    
    inv = nil
    assert_nothing_raised { inv = Invoice.create! :client => Factory.create_client }
    
    assert_equal 0.0.to_s, inv.amount.to_s
    
    assert_equal 0.0.to_s, (inv.sub_total+inv.taxes_total).to_s
    
  end
  
  def test_activity_move

    client_src = Factory.create_client
    client_dest = Factory.create_client

    create_act_args = {:occurred_on => (DateTime.now << 1), :client => client_src}
    
    labor = Factory.create_labor( {}, create_act_args.merge({:cost => 1.99}) )
    material = Factory.create_material( {}, create_act_args)
    proposal = Factory.create_proposal( {}, create_act_args)
    adjustment = Factory.create_adjustment( {}, create_act_args.merge({:tax => 26.00}))

    subactivities = [labor, material, proposal, adjustment]
    
    invoice_src = Invoice.create!(
      :client => client_src, 
      :issued_on => DateTime.now,
      :activity_types => @activity_types 
    )

    invoice_dest = Invoice.create!(
      :client => client_dest, 
      :issued_on => DateTime.now
    )
    
    subactivities.each do |activity_type|
      activity_type.reload

      assert_equal invoice_src.id, activity_type.activity.invoice_id
      assert_equal client_src.id, activity_type.activity.client_id
    end

    assert_equal 2448.99.to_s, invoice_src.amount.to_s
    
    assert_equal 2448.99.to_s, (invoice_src.sub_total+invoice_src.taxes_total).to_s

    assert_nothing_raised do 
      subactivities.each do |activity_type|
        activity_type.activity.move_to_invoice invoice_dest
      end
    end

    assert_equal 2448.99.to_s, invoice_dest.amount.to_s
    
    assert_equal 2448.99.to_s, (invoice_dest.sub_total+invoice_dest.taxes_total).to_s

    subactivities.each do |at|
      assert_equal invoice_dest.id, at.activity.invoice_id
      assert_equal client_src.id, at.activity.client_id
    end
  
    assert_nothing_raised do 
      labor.activity.move_to_invoice invoice_src
    end

    assert_equal invoice_src.id, labor.activity.invoice_id
    assert_equal client_src.id, labor.activity.client_id

    assert_equal 2447.0.to_s, invoice_dest.amount.to_s
    
    assert_equal 2447.0.to_s, (invoice_dest.sub_total+invoice_dest.taxes_total).to_s

    invoice_src.is_published = true
    invoice_src.save!

    # Assert fail!
    labor.activity.reload
    assert_raise(StandardError) { labor.activity.move_to_invoice invoice_dest }
    
    # Assert fail!
    material.activity.reload
    assert_raise(StandardError) { material.activity.move_to_invoice invoice_src }
    
  end
  
  private
  
  def set_published(inv, published_state)
    inv.is_published = published_state
    inv.save!
  end

end