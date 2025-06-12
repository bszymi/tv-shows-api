require 'rails_helper'

RSpec.describe Distributor, type: :model do
  describe 'associations' do
    it { should have_many(:tv_shows).dependent(:destroy) }
  end

  describe 'validations' do
    subject { Distributor.new(name: 'Test Distributor') }
    
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
  end
end