require 'mime/message'

module Gmail
  class Message
    # Raised when given label doesn't exists.
    class NoLabelError < Exception; end

    attr_reader :uid, :msgid, :headers

    #TODO refactor to options hash
    def initialize(mailbox, msgid, uid, thrid = nil, size = nil, envelope = nil, flags = nil, labels = nil, headers = nil)
      @mailbox = mailbox
      @gmail   = mailbox.instance_variable_get("@gmail") if mailbox
      @msgid = msgid
      @uid = uid
      @thread_id = thrid
      @size = size
      @envelope = envelope
      @flags = flags
      @labels = labels
      @headers = headers
    end

    #TODO get rid of all such lazy loading, as it confuses a lot
    def labels
      @labels ||= @gmail.conn.uid_fetch(uid, "X-GM-LABELS")[0].attr["X-GM-LABELS"]
    end

    def thread_id
      @thread_id ||= @gmail.conn.uid_fetch(uid, "X-GM-THRID")[0].attr["X-GM-THRID"]
    end

    def uid
      @uid ||= @gmail.conn.uid_search(['HEADER', 'Message-ID', message_id])[0]
    end

    def read?
      return flags.include? :Seen
    end

    # Mark message with given flag.
    def flag(name)
      !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "+FLAGS", [name]) }
    end

    # Unmark message.
    def unflag(name)
      !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "-FLAGS", [name]) }
    end

    # Do commonly used operations on message.
    def mark(flag)
      case flag
        when :read    then read!
        when :unread  then unread!
        when :deleted then delete!
        when :spam    then spam!
      else
        flag(flag)
      end
    end

    # Mark this message as a spam.
    def spam!
      move_to('[Gmail]/Spam')
    end

    # Mark as read.
    def read!
      flag(:Seen)
    end

    # Mark as unread.
    def unread!
      unflag(:Seen)
    end

    # Mark message with star.
    def star!
      !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "+X-GM-LABELS", ['\Starred']) }
    end

    # Remove message from list of starred.
    def unstar!
      !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "-X-GM-LABELS", ['\Starred']) }
    end

    def add_label(name)
      !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "+X-GM-LABELS", [name]) }
    end

    def add_label!(name)
      label(name)
    rescue Gmail::Message::NoLabelError
      @gmail.labels.add(Net::IMAP.encode_utf7(name))
      add_label(name)
    end

    def remove_label!(name)
      !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "-X-GM-LABELS", [name]) }
    end


    # Move to trash / bin.
    def delete!
      @mailbox.messages.delete(uid)
      #flag(:deleted)

      # For some, it's called "Trash", for others, it's called "Bin". Support both.

      #trash =  @gmail.labels.exist?('[Gmail]/Bin') ? '[Gmail]/Bin' : '[Gmail]/Trash'
      !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "+X-GM-LABELS", ['\Trash']) }
      #move_to(trash) unless %w[[Gmail]/Spam [Gmail]/Bin [Gmail]/Trash].include?(@mailbox.name)
    end

    # Archive this message.
    def archive!
      move_to('[Gmail]/All Mail')
    end

    # Move to given box and delete from others.
    def move_to(name, from=nil)
      label(name)#, from)
      delete! if !%w[[Gmail]/Bin [Gmail]/Trash].include?(name)
    end
    alias :move :move_to

    # Move message to given and delete from others. When given mailbox doesn't
    # exist then it will be automaticaly created.
    def move_to!(name, from=nil)
      label!(name, from) && delete!
    end
    alias :move! :move_to!

    # Mark this message with given label. When given label doesn't exist then
    # it will raise <tt>NoLabelError</tt>.
    #
    # See also <tt>Gmail::Message#label!</tt>.
    def label(name)
      @gmail.mailbox(Net::IMAP.encode_utf7(from || @mailbox.external_name)) { @gmail.conn.uid_copy(uid, Net::IMAP.encode_utf7(name)) }
    rescue
      raise NoLabelError, "Label '#{name}' doesn't exist!"
    end

    # Mark this message with given label. When given label doesn't exist then
    # it will be automaticaly created.
    #
    # See also <tt>Gmail::Message#label</tt>.
    #def label!(name)
    #  label(name)
    #rescue NoLabelError
    #  @gmail.labels.add(Net::IMAP.encode_utf7(name))
    #  label(name)
    #end
    #alias :add_label :label!
    #alias :add_label! :label!

    # Remove given label from this message.
    #def remove_label!(name)
    #  !!@gmail.mailbox(@mailbox.name) { @gmail.conn.uid_store(uid, "-X-GM-LABELS", [name]) }
    #end
    #alias :delete_label! :remove_label!

    def inspect
      "#<Gmail::Message#{'0x%04x' % (object_id << 1)} mailbox=#{@mailbox.external_name}#{' uid='+@uid.to_s if @uid}#{' message_id='+@message_id.to_s if @message_id}>"
    end

    def method_missing(meth, *args, &block)
      # Delegate rest directly to the message.
      if envelope.respond_to?(meth)
        envelope.send(meth, *args, &block)
      elsif message.respond_to?(meth)
        message.send(meth, *args, &block)
      else
        super(meth, *args, &block)
      end
    end

    def respond_to?(meth, *args, &block)
      if envelope.respond_to?(meth)
        return true
      elsif message.respond_to?(meth)
        return true
      else
        super(meth, *args, &block)
      end
    end

    def size
      @size ||= @gmail.mailbox(@mailbox.name) {
        @gmail.conn.uid_fetch(uid, "RFC822.SIZE")[0].attr["RFC822.SIZE"]
      }
    end

    def envelope
      @envelope ||= @gmail.mailbox(@mailbox.name) {
        @gmail.conn.uid_fetch(uid, "ENVELOPE")[0].attr["ENVELOPE"]
      }
    end

    def message
      @message ||= Mail.new(@gmail.mailbox(@mailbox.name) {
        @gmail.conn.uid_fetch(uid, "RFC822")[0].attr["RFC822"] # RFC822
      })
    end
    alias_method :raw_message, :message

    def flags
      @flags ||= Mail.new(@gmail.conn.uid_fetch(uid, "FLAGS")[0].attr["FLAGS"])
    end
  end # Message
end # Gmail
