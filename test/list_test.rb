require 'riot'
require 'test/unit'

require 'rubygems'
gem 'activerecord', '>= 2.1'
require 'active_record'

require "#{ File.dirname __FILE__ }/../init"

ActiveRecord::Base.
    establish_connection :adapter => 'sqlite3', :database => ':memory:'

#ActiveRecord::Base.logger = ActiveSupport::BufferedLogger.new(STDERR)
#ActiveRecord::Base.colorize_logging = false

def setup_db
  ActiveRecord::Schema.define(:version => 1) do
    create_table :mixins do |mixins|
      mixins.integer :pos
      mixins.integer :parent_id
      mixins.timestamps
    end
  end
end

def teardown_db
  ActiveRecord::Base.connection.tables.
      each { |table| ActiveRecord::Base.connection.drop_table table }
end

class Mixin < ActiveRecord::Base
end

class ListMixin < Mixin
  acts_as_list :column => 'pos', :scope => :parent
end
class ListMixinSub1 < ListMixin; end
class ListMixinSub2 < ListMixin; end

class ListWithStringScopeMixin < ActiveRecord::Base
  acts_as_list :column => 'pos', :scope => 'parent_id = #{ parent_id }'
  set_table_name 'mixins'
end

setup_db
(1..7).each { |i| ListMixin.create! :pos => i, :parent_id => 5 }

context 'Listed items' do

  asserts 'order' do
    ListMixin.list('parent_id = 5', :select => 'id').map! { |r| r.id }
  end.equals [1, 2, 3, 4, 5, 6, 7]

  asserts 'order after second item moved lower' do
    ListMixin.find(2).move_lower
    ListMixin.list('parent_id = 5', :select => 'id').map! { |r| r.id }
  end.equals [1, 3, 2, 4, 5, 6, 7]

  asserts 'order after second item moved higher' do
    ListMixin.find(2).move_higher
    ListMixin.list('parent_id = 5', :select => 'id').map! { |r| r.id }
  end.equals [1, 2, 3, 4, 5, 6, 7]

  asserts 'order after first item moved to bottom' do
    ListMixin.find(1).move_to_bottom
    ListMixin.list('parent_id = 5', :select => 'id').map! { |r| r.id }
  end.equals [2, 3, 4, 5, 6, 7, 1]

  asserts 'order after last item moved to top' do
    ListMixin.find(4).move_to_top
    ListMixin.list('parent_id = 5', :select => 'id').map! { |r| r.id }
  end.equals [4, 2, 3, 5, 6, 7, 1]

  asserts 'order after next to last item moved to bottom' do
    ListMixin.find(3).move_to_bottom
    ListMixin.list('parent_id = 5', :select => 'id').map! { |r| r.id }
  end.equals [4, 2, 5, 6, 7, 1, 3]

  asserts 'lower item of item 1' do
    ListMixin.find(1).lower_item
  end.equals ListMixin.find(3)
  asserts('higher item of item 4') { ListMixin.find(4).higher_item }.nil

  asserts 'higher item of item 5' do
    ListMixin.find(5).higher_item
  end.equals ListMixin.find(2)
  asserts('lower item of item 3') { ListMixin.find(3).lower_item }.nil

  asserts 'proxy options for listed in :parent_id == 1' do
    ListMixin.list(:parent_id => 1).proxy_options
  end.equals :conditions => { :parent_id => 1 }, :order => 'pos'

  asserts 'position of list creating item' do
    ListMixin.create(:parent_id => 20).pos
  end.equals 1
  should('be the only item in new list') do
    only_item = ListMixin.list(:parent_id => 20).first
    only_item.first? and only_item.last?
  end
  asserts 'position of second listed item' do
    ListMixin.create(:parent_id => 20).pos
  end.equals 2
  should 'not be the first, but the last in existing list' do
    last = ListMixin.list(:parent_id => 20).last
    !last.first? and last.last?
  end

  asserts 'position of lower item of fourth item inserted at pos 3' do
    ListMixin.list('parent_id = 5').fourth.
    tap { |item| item.insert_at 3 }.
    lower_item.pos
  end.equals 4

  context 'removal' do
    should 'not shift twice after being removed from list' do
      ListMixin.find(2).
          tap { |item| item.remove_from_list }.
          tap { |item| item.destroy }

      ListMixin.list('parent_id = 5', :select => 'pos').map! { |r| r.pos }.
      inject(0) { |last, current| current == last + 1 ? current : last } == 6
    end
    
    should 'decrease position of lower items' do
      ListMixin.destroy 3

      ListMixin.list('parent_id = 5', :select => 'pos').map! { |r| r.pos }.
      inject(0) { |last, current| current == last + 1 ? current : last } == 5
    end
  end

  context 'with string based scope' do
    asserts 'position of list creating item' do
      ListWithStringScopeMixin.create(:parent_id => 33).pos
    end.equals 1
    should('be the only item in new list') do
      only_item = ListWithStringScopeMixin.list(:parent_id => 33).first
      only_item.first? and only_item.last?
    end
  end

  asserts 'be ordered even if scope value is nil' do
    first, second, third = Array.new(3) { ListMixin.create }
    second.move_higher

    [second, first, third]
  end.equals ListMixin.list('parent_id IS NULL', :offset => 2)

  should 'not be listed after removed from list' do
    not ListMixin.find(1).tap { |item| item.remove_from_list }.listed?
  end
  asserts 'position to be nil after removed from list' do
    ListMixin.find(4).tap { |item| item.remove_from_list }.pos
  end.nil

end

class ListSubTest < Test::Unit::TestCase

  def setup
    teardown_db
    setup_db
    (1..4).each { |i| ((i % 2 == 1) ? ListMixinSub1 : ListMixinSub2).create! :pos => i, :parent_id => 5000 }
  end

  def teardown
    teardown_db
    setup_db
    (1..7).each { |i| ListMixin.create! :pos => i, :parent_id => 5 }
  end

  def test_reordering
    assert_equal [1, 2, 3, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    ListMixin.find(2).move_lower
    assert_equal [1, 3, 2, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    ListMixin.find(2).move_higher
    assert_equal [1, 2, 3, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    ListMixin.find(1).move_to_bottom
    assert_equal [2, 3, 4, 1], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    ListMixin.find(1).move_to_top
    assert_equal [1, 2, 3, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    ListMixin.find(2).move_to_bottom
    assert_equal [1, 3, 4, 2], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    ListMixin.find(4).move_to_top
    assert_equal [4, 1, 3, 2], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)
  end

  def test_move_to_bottom_with_next_to_last_item
    assert_equal [1, 2, 3, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)
    ListMixin.find(3).move_to_bottom
    assert_equal [1, 2, 4, 3], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)
  end

  def test_next_prev
    assert_equal ListMixin.find(2), ListMixin.find(1).lower_item
    assert_nil ListMixin.find(1).higher_item
    assert_equal ListMixin.find(3), ListMixin.find(4).higher_item
    assert_nil ListMixin.find(4).lower_item
  end

  def test_injection
    item = ListMixin.new("parent_id"=>1)
    expected_options = { :conditions => { :parent_id => 1 }, :order => 'pos' }
    assert_equal expected_options, ListMixin.listed_with(item).proxy_options
    assert_equal "pos", item.position_column
  end

  def test_insert_at
    new = ListMixin.create("parent_id" => 20)
    assert_equal 1, new.pos

    new = ListMixinSub1.create("parent_id" => 20)
    assert_equal 2, new.pos

    new = ListMixinSub2.create("parent_id" => 20)
    assert_equal 3, new.pos

    new4 = ListMixin.create("parent_id" => 20)
    assert_equal 4, new4.pos

    new4.insert_at(3)
    assert_equal 3, new4.pos

    new.reload
    assert_equal 4, new.pos

    new.insert_at(2)
    assert_equal 2, new.pos

    new4.reload
    assert_equal 4, new4.pos

    new5 = ListMixinSub1.create("parent_id" => 20)
    assert_equal 5, new5.pos

    new5.insert_at(1)
    assert_equal 1, new5.pos

    new4.reload
    assert_equal 5, new4.pos
  end

  def test_delete_middle
    assert_equal [1, 2, 3, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    ListMixin.find(2).destroy

    assert_equal [1, 3, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    assert_equal 1, ListMixin.find(1).pos
    assert_equal 2, ListMixin.find(3).pos
    assert_equal 3, ListMixin.find(4).pos

    ListMixin.find(1).destroy

    assert_equal [3, 4], ListMixin.find(:all, :conditions => 'parent_id = 5000', :order => 'pos').map(&:id)

    assert_equal 1, ListMixin.find(3).pos
    assert_equal 2, ListMixin.find(4).pos
  end

end
