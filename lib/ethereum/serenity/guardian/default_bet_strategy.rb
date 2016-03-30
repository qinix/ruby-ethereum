# -*- encoding : ascii-8bit -*-

module Ethereum
  module Guardian

    class DefaultBetStrategy

      include Constant
      include Config

      def initialize(genesis_state, key,
                     clockwrong: false, bravery: 0.92, crazy_bet: false,
                     double_block_suicide: 2**200, double_bet_suicide: 2**200,
                     min_gas_price: 10**9)
        Utils.debug 'Initializing betting strategy'

        @db = genesis_state.db # bet strategy's database

        @id = Utils.mkid # id for network simulator
        @key = key # Guardian's private key
        @addr = ECDSAAccount.privtoaddr key

        # This counter is incremented every time a guardian joins;
        # it allows us to re-process the guardian set and refresh the guardians
        # that we have
        @guardian_signups = genesis_state.call_casper('getGuardianSignups', [])

        # A dict of opinion objects containing the current opinions of all
        # guardians
        @opinions = {}
        @bets = {} # A dict of lists of bets received from guardians
        @probs = [] # the probabilities that you are betting

        @finalized_hashes = [] # your finalized block hashes
        @stateroots = [] # your state roots
        @counters = [] # which counters have been processed

        # A hash containing the highest-sequence-number bet processed for each
        # guardian
        @highest_bet_processed = {}
        @time_received = {} # the time when you received an object

        # Hash lookup map; used mainly to check whether or not something has
        # already been received and processed
        @objects = {}

        # Blocks selected for each height
        @blocks = []

        # When you last explicitly requested to ask for a block; stored to
        # prevent excessively frequent lookups
        @last_asked_for_block = {}

        # When you last explicitly requested to ask for bets from a given
        # guardian; stored to prevent excessively frequent lookups
        @last_asked_for_bets = {}

        @txpool = {} # Pool of transactions worth including

        # Map of hash -> (tx, [(blknum, index), ...]) for transactions that are
        # in blocks that are not fully confirmed
        @finalized_txindex = {}

        # Counter for number of times a transaction entered an exceptional
        # condition
        @tx_exceptions = {}

        @last_bet_made = 0 # stored to prevent excessively frequent betting
        @last_time_sent_getblocks = 0 # stored to prevent frequent sent getblocks msg

        @index = -1 # your guardian index
        @former_index = nil

        @genesis_state_root = genesis_state.root
        @genesis_time = Utils.big_endian_to_int genesis_state.get_storage(GENESIS_TIME, WORD_ZERO)

        @last_block_produced = -1
        # next height at which you are eligible to produce (could be nil)
        @next_block_to_produce = -1

        @clockwrong = clockwrong
        @crazy_bet = crazy_bet # am I making crazy bets?
        @bravery = bravery # how quickly to converge toward finalization
        raise ArgumentError, "invalid bravery factor" unless bravery > 0 && bravery <= 1

        # What block number to create two blocks at, destroying my guardian slot
        # (for testing purposes; for non-byzantine nodes set to some really high
        # number)
        @double_block_suicide = double_block_suicide
        # What seq to create two bets at (also destructively, for testing)
        @double_bet_suicide = double_bet_suicide

        # Next submission delay (should be 0 on livenet; nonzero for testing)
        @next_submission_delay = @clockwrong ? ((-BLKTIME*2)...(BLKTIME*6)).to_a.sample : 0

        # List of proposers for blocks, calculated into the future just-in-time
        @proposers = []

        @prevhash = WORD_ZERO # for betting
        @seq = 0  # for betting

        @tracked_tx_hashes = []

        # If we only partially calculate state roots, store the index at which
        # to start calculating next time you make a bet
        @calc_state_roots_from = 0 

        @min_gas_price = min_gas_price # minimum gas price I accept

        # Create my guardian set
        #update_guardian_set genesis_state
        Utils.debug "Found #{@opinions.size} guardians in genesis"

        # The height at which this guardian is added
        @induction_height = @index >= 0 ? genesis_state.call_casper('getGuardianInductionHeight', [@index]) : 2**100
        Utils.debug "Initialized guardian", address: Utils.encode_hex(@addr), index: @index, induction_height: @induction_height

        @withdrawn = false
        @max_finalized_height = -1 # max height which is finalized from your point of view
        @recently_discovered_blocks = []

        # When will I suicide?
        if @double_block_suicide < 2**40
          if @double_block_suicide < @next_block_to_produce
            Utils.debug "Suiciding at block #{@next_block_to_produce}"
          else
            Utils.debug "Suiciding at some block after #{@double_block_suicide}"
          end
        end
        Utils.debug "List of", proposers: @proposers

        # Am I byzantine?
        @byzantine = @crazy_bet || @double_block_suicide < 2**80 || @double_bet_suicide < 2**80
      end

    end

  end
end