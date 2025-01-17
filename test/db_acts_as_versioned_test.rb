# frozen_string_literal: true

require_relative "test_helper"

class DbActsAsVersionedTest < ActiveSupport::TestCase
  fixtures :pages, :page_versions, :locked_pages, :locked_pages_revisions, :authors, :landmarks, :landmark_versions
  set_fixture_class page_versions: Page::Version

  def test_saves_versioned_copy
    p = Page.create! title: "first title", body: "first body"
    assert !p.new_record?
    assert_equal 1, p.versions.size
    assert_equal 1, p.version
    assert_instance_of Page.versioned_class, p.versions.first
    first_version = p.versions.first
    assert_equal "first title", first_version.title, "The first version should match the created object value"
    p.update title: "changed"
    assert_equal 2, p.versions.size
    last_version = p.versions.last
    assert_equal "changed", last_version.title, "The last version should match the last change"
  end

  def test_saves_without_revision
    p = pages(:welcome)
    old_versions = p.versions.count

    p.save_without_revision

    p.without_revision do
      p.update title: "changed"
    end

    assert_equal old_versions, p.versions.count
  end

  def test_rollback_with_version_number
    p = pages(:welcome)
    assert_equal 24, p.version
    assert_equal "Welcome to the weblog", p.title

    assert p.revert_to!(23), "Couldn't revert to 23"
    assert_equal 23, p.version
    assert_equal "Welcome to the weblg", p.title
  end

  def test_versioned_class_name
    assert_equal "Version", Page.versioned_class_name
    assert_equal "LockedPageRevision", LockedPage.versioned_class_name
  end

  def test_versioned_class
    assert_equal Page::Version,                  Page.versioned_class
    assert_equal LockedPage::LockedPageRevision, LockedPage.versioned_class
  end

  def test_special_methods
    assert_nothing_raised { pages(:welcome).feeling_good? }
    assert_nothing_raised { pages(:welcome).versions.first.feeling_good? }
    assert_nothing_raised { locked_pages(:welcome).hello_world }
    assert_nothing_raised { locked_pages(:welcome).versions.first.hello_world }
  end

  def test_rollback_with_version_class
    p = pages(:welcome)
    assert_equal 24, p.version
    assert_equal "Welcome to the weblog", p.title

    assert p.revert_to!(p.versions.find_by_version(23)), "Couldn't revert to 23"
    assert_equal 23, p.version
    assert_equal "Welcome to the weblg", p.title
  end

  def test_rollback_fails_with_invalid_revision
    p = locked_pages(:welcome)
    assert !p.revert_to!(locked_pages(:thinking))
  end

  # ActiveRecord::StaleObjectError: Attempted to update a stale object: LockedPage::LockedPageRevision

  # def test_saves_versioned_copy_with_options
  #   p = LockedPage.create! :title => 'first title'
  #   assert !p.new_record?
  #   assert_equal 1, p.versions.size
  #   assert_instance_of LockedPage.versioned_class, p.versions.first
  # end

  def test_rollback_with_version_number_with_options
    p = locked_pages(:welcome)
    assert_equal "Welcome to the weblog", p.title
    assert_equal "LockedPage", p.versions.first.version_type

    assert p.revert_to!(p.versions.first.lock_version), "Couldn't revert to 23"
    assert_equal "Welcome to the weblg", p.title
    assert_equal "LockedPage", p.versions.first.version_type
  end

  def test_rollback_with_version_class_with_options
    p = locked_pages(:welcome)
    assert_equal "Welcome to the weblog", p.title
    assert_equal "LockedPage", p.versions.first.version_type

    assert p.revert_to!(p.versions.first), "Couldn't revert to 1"
    assert_equal "Welcome to the weblg", p.title
    assert_equal "LockedPage", p.versions.first.version_type
  end

  # ActiveRecord::StaleObjectError: Attempted to update a stale object: LockedPage::LockedPageRevision

  # def test_saves_versioned_copy_with_sti
  #   p = SpecialLockedPage.create! :title => 'first title'
  #   assert !p.new_record?
  #   assert_equal 1, p.versions.size
  #   assert_instance_of LockedPage.versioned_class, p.versions.first
  #   assert_equal 'SpecialLockedPage', p.versions.first.version_type
  # end

  def test_rollback_with_version_number_with_sti
    p = locked_pages(:thinking)
    assert_equal "So I was thinking", p.title

    assert p.revert_to!(p.versions.first.lock_version), "Couldn't revert to 1"
    assert_equal "So I was thinking!!!", p.title
    assert_equal "SpecialLockedPage", p.versions.first.version_type
  end

  def test_lock_version_works_with_versioning
    p = locked_pages(:thinking)
    p2 = LockedPage.find(p.id)

    assert_raises(ActiveRecord::StaleObjectError) do
      p2.title = "stale title"
      p2.save
    end
  end

  def test_version_if_condition
    p = Page.create! title: "title"
    assert_equal 1, p.version

    Page.feeling_good = false
    p.save
    assert_equal 1, p.version
    Page.feeling_good = true
  end

  def test_version_if_condition2
    # set new if condition
    Page.class_eval do
      def new_feeling_good
        title[0..0] == "a"
      end
      alias_method :old_feeling_good, :feeling_good?
      alias_method :feeling_good?, :new_feeling_good
    end

    p = Page.create! title: "title"
    assert_equal 1, p.version # version does not increment
    assert_equal 1, p.versions.count

    p.update(title: "new title")
    assert_equal 1, p.version # version does not increment
    assert_equal 1, p.versions.count

    p.update(title: "a title")
    assert_equal 2, p.version
    assert_equal 2, p.versions.count

    # reset original if condition
    Page.class_eval { alias_method :feeling_good?, :old_feeling_good }
  end

  def test_version_if_condition_with_block
    # set new if condition
    old_condition = Page.version_condition
    Page.version_condition = proc { |page| page.title[0..0] == "b" }

    p = Page.create! title: "title"
    assert_equal 1, p.version # version does not increment
    assert_equal 1, p.versions.count

    p.update(title: "a title")
    assert_equal 1, p.version # version does not increment
    assert_equal 1, p.versions.count

    p.update(title: "b title")
    assert_equal 2, p.version
    assert_equal 2, p.versions.count

    # reset original if condition
    Page.version_condition = old_condition
  end

  def test_version_no_limit
    p = Page.create! title: "title", body: "first body"
    p.save
    p.save
    5.times do |i|
      p.title = "title#{i}"
      p.save
      assert_equal "title#{i}", p.title
      assert_equal (i + 2), p.version
    end
  end

  # ActiveRecord::StaleObjectError: Attempted to update a stale object: LockedPage::LockedPageRevision

  # def test_version_max_limit
  #   p = LockedPage.create! :title => "title"
  #   p.update(:title => "title1")
  #   p.update(:title => "title2")
  #   5.times do |i|
  #     p.title = "title#{i}"
  #     p.save
  #     assert_equal "title#{i}", p.title
  #     assert_equal (i+4), p.lock_version
  #     assert p.versions.size <= 2, "locked version can only store 2 versions"
  #   end
  # end

  def test_track_altered_attributes_default_value
    assert !Page.track_altered_attributes
    assert LockedPage.track_altered_attributes
    assert SpecialLockedPage.track_altered_attributes
  end

  # ActiveRecord::StaleObjectError: Attempted to update a stale object: LockedPage::LockedPageRevision

  # def test_track_altered_attributes
  #   p = LockedPage.create! :title => "title"
  #   assert_equal 1, p.lock_version
  #   assert_equal 1, p.versions.size
  #
  #   p.body = 'whoa'
  #   assert !p.save_version?
  #   p.save
  #   assert_equal 2, p.lock_version # still increments version because of optimistic locking
  #   assert_equal 1, p.versions.size
  #
  #   p.title = 'updated title'
  #   assert p.save_version?
  #   p.save
  #   assert_equal 3, p.lock_version
  #   assert_equal 1, p.versions.size # version 1 deleted
  #
  #   p.title = 'updated title!'
  #   assert p.save_version?
  #   p.save
  #   assert_equal 4, p.lock_version
  #   assert_equal 2, p.versions.size # version 1 deleted
  # end

  def test_find_versions
    assert_equal 1, locked_pages(:welcome).versions.where("title LIKE ?", "%weblog%").count
  end

  def test_find_version
    assert_equal page_versions(:welcome_1), pages(:welcome).versions.find_by_version(23)
  end

  def test_has_many_through
    assert_equal [authors(:caged), authors(:mly)], pages(:welcome).authors
  end

  def test_has_many_through_with_custom_association
    assert_equal [authors(:caged), authors(:mly)], pages(:welcome).revisors
  end

  def test_referential_integrity
    pages(:welcome).destroy
    assert_equal 0, Page.count
    assert_equal 0, Page::Version.count
  end

  def test_association_options
    association = Page.reflect_on_association(:versions)
    options = association.options
    assert_equal :destroy, options[:dependent]

    association = Widget.reflect_on_association(:versions)
    options = association.options
    assert_equal :nullify, options[:dependent]
    assert_equal "widget_id", options[:foreign_key]

    widget = Widget.create! name: "new widget"
    assert_equal 1, Widget.count
    assert_equal 1, Widget.versioned_class.count
    widget.destroy
    assert_equal 0, Widget.count
    assert_equal 1, Widget.versioned_class.count
  end

  def test_versioned_records_should_belong_to_parent
    page = pages(:welcome)
    page_version = page.versions.last
    assert_equal page, page_version.page
  end

  def test_unaltered_attributes
    landmarks(:washington).attributes = landmarks(:washington).attributes.except("id")
    assert !landmarks(:washington).changed?
  end

  def test_unchanged_string_attributes
    landmarks(:washington).attributes = landmarks(:washington).attributes.except("id").inject({}) do |params, (key, value)|
      params.update(key => value.to_s)
    end
    assert !landmarks(:washington).changed?
  end

  def test_should_find_earliest_version
    assert_equal page_versions(:welcome_1), pages(:welcome).versions.earliest
  end

  def test_should_find_latest_version
    assert_equal page_versions(:welcome_2), pages(:welcome).versions.latest
  end

  def test_should_find_previous_version
    assert_equal page_versions(:welcome_1), page_versions(:welcome_2).previous
    assert_equal page_versions(:welcome_1), pages(:welcome).versions.before(page_versions(:welcome_2))
  end

  def test_should_find_next_version
    assert_equal page_versions(:welcome_2), page_versions(:welcome_1).next
    assert_equal page_versions(:welcome_2), pages(:welcome).versions.after(page_versions(:welcome_1))
  end

  def test_should_find_version_count
    assert_equal 2, pages(:welcome).versions.size
  end

  def test_if_changed_creates_version_if_a_listed_column_is_changed
    landmarks(:washington).name = "Washington"
    assert landmarks(:washington).changed?
    assert landmarks(:washington).altered?
  end

  def test_if_changed_creates_version_if_all_listed_columns_are_changed
    landmarks(:washington).name = "Washington"
    landmarks(:washington).latitude = 1.0
    landmarks(:washington).longitude = 1.0
    assert landmarks(:washington).changed?
    assert landmarks(:washington).altered?
  end

  def test_if_changed_does_not_create_new_version_if_unlisted_column_is_changed
    landmarks(:washington).doesnt_trigger_version = "This should not trigger version"
    assert landmarks(:washington).changed?
    assert !landmarks(:washington).altered?
  end

  def test_without_locking_temporarily_disables_optimistic_locking
    enabled1 = false
    block_called = false

    ActiveRecord::Base.lock_optimistically = true
    LockedPage.without_locking do
      enabled1 = ActiveRecord::Base.lock_optimistically
      block_called = true
    end
    enabled2 = ActiveRecord::Base.lock_optimistically

    assert block_called
    assert !enabled1
    assert enabled2
  end

  def test_without_locking_reverts_optimistic_locking_settings_if_block_raises_exception
    assert_raises(RuntimeError) do
      LockedPage.without_locking do
        raise "oh noes"
      end
    end
    assert ActiveRecord::Base.lock_optimistically
  end
end
