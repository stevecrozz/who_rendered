# frozen_string_literal: true

# Stands in for a third-party gem that renders from inside its own code.
module FakeGem
  BLOCK_LINE = __LINE__ + 3

  def fake_gem_block
    head :forbidden
  end
end
