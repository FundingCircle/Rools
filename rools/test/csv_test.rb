#
# Testing Rools
#
# Pat Cappelaere
#
# Wed Apr 25 20:50:00 EDT 2007
#

require 'test/unit'
require 'rools'
require 'rools/base'
require 'logger'

class Person
  attr_accessor :name, :gender, :maritalStatus
  
  def initialize(name, gender, maritalStatus)
    @name          = name
    @gender        = gender
    @maritalStatus = maritalStatus
  end
end


class Hour
  attr_accessor :val
  
  def initialize( val )
    @val = val
  end
  
  def >= ( val)
    return @val >= val
  end
  
  def <= (val)
    @val <= val
  end
end

class CSVTest < Test::Unit::TestCase

  def setup
    #Rools::Base.logger = Logger.new(STDOUT)
  end
  
  def test_greetings
    rules  = Rools::RuleSet.new 'test/data/greetings.csv'
	status = rules.assert Hour.new(1)
	assert status == :pass
	assert $greeting = "Good Morning"
	
	rules.delete_facts()
	status = rules.assert Hour.new( 13)
	assert status == :pass
	assert $greeting = "Good Afternoon"
	
	rules.delete_facts()
	status = rules.assert Hour.new( 19)
	assert status == :pass
	assert $greeting = "Good Night"
  end
	
  def test_salutations
    sally = Person.new("sally", "Married", 43)
    peggy = Person.new("peggy", "Single", 43)
    joe   = Person.new("Joe", "Single", 43)
    john  = Person.new("Little John", "Single", 9)
    
    rules  = Rools::RuleSet.new 'test/data/salutations.csv'
	status = rules.assert sally
	assert status == :pass
	assert $salutation = "Mrs."
	
	rules.delete_facts()
	status = rules.assert peggy
	assert status == :pass
	assert $salutation = "Ms."
	
	rules.delete_facts()
	status = rules.assert joe
	assert status == :pass
	assert $salutation = "Mr."

	rules.delete_facts()
	status = rules.assert john
	assert status == :pass
	assert $salutation = "Little"

  end
end