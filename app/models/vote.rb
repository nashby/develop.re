class Vote < ActiveRecord::Base
  belongs_to :user
  belongs_to :story

  STORY_REASONS = {
    "S" => "Spam",
    "A" => "Already Posted",
    "L" => "Poorly Titled",
    "T" => "Poorly Tagged",
    "O" => "Off-topic",
    "" => "Cancel",
  }

  COMMENT_REASONS = {
    "O" => "Off-topic",
    "I" => "Incorrect",
    "M" => "Me-too",
    "T" => "Troll",
    "S" => "Spam",
    "" => "Cancel",
  }

  def self.votes_by_user_for_stories_hash(user, stories)
    votes = []
    Vote.where(:user_id => user, :story_id => stories,
    :comment_id => nil).each do |v|
      votes[v.story_id] = v.vote
    end

    votes
  end

  def self.comment_votes_by_user_for_story_hash(user_id, story_id)
    votes = {}

    Vote.find(:all, :conditions => [ "user_id = ? AND story_id = ? AND " +
    "comment_id IS NOT NULL", user_id, story_id ]).each do |v|
      votes[v.comment_id] = { :vote => v.vote, :reason => v.reason }
    end

    votes
  end

  def self.vote_thusly_on_story_or_comment_for_user_because(vote, story_id,
  comment_id, user_id, reason, update_counters = true)
    v = if comment_id
      Vote.find_or_initialize_by_user_id_and_story_id_and_comment_id(user_id,
        story_id, comment_id)
    else
      Vote.find_or_initialize_by_user_id_and_story_id(user_id, story_id)
    end

    if !v.new_record? && v.vote == vote
      return
    end

    upvote = 0
    downvote = 0

    Vote.transaction do
      # unvote
      if vote == 0
        if !v.new_record?
          if v.vote == -1
            downvote = -1
          else
            upvote = -1
          end
        end

        v.destroy

      # new vote or change vote
      else
        if v.new_record?
          if vote == -1
            downvote = 1
          else
            upvote = 1
          end
        elsif v.vote == -1
          # changing downvote to upvote
          downvote = -1
          upvote = 1
        elsif v.vote == 1
          # changing upvote to downvote
          upvote = -1
          downvote = 1
        end

        v.vote = vote
        v.reason = reason
        v.save!
      end

      if update_counters && (downvote != 0 || upvote != 0)
        if v.comment_id
          Comment.update_counters v.comment_id, :downvotes => downvote,
            :upvotes => upvote

          if (c = Comment.find(v.comment_id)) && c.user_id != user_id
            Keystore.increment_value_for("user:#{c.user_id}:karma")
          end
        else
          Story.update_counters v.story_id, :downvotes => downvote,
            :upvotes => upvote

          if (s = Story.find(v.story_id)) && s.user_id != user_id
            Keystore.increment_value_for("user:#{s.user_id}:karma")
          end
        end
      end
    end
  end
end
