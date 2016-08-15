require 'bit-struct'
require 'zlib'

class TraceConvert
  class Macsim
    module CPU_OPCODE
      XED_CATEGORY_INVALID    = 0
      XED_CATEGORY_3DNOW      = 1
      XED_CATEGORY_AES        = 2
      XED_CATEGORY_AVX        = 3
      XED_CATEGORY_AVX2       = 4
      XED_CATEGORY_AVX2GATHER = 5
      XED_CATEGORY_BDW        = 6
      XED_CATEGORY_BINARY     = 7
      XED_CATEGORY_BITBYTE    = 8
      XED_CATEGORY_BMI1       = 9
      XED_CATEGORY_BMI2       = 10
      XED_CATEGORY_BROADCAST  = 11
      XED_CATEGORY_CALL       = 12
      XED_CATEGORY_CMOV       = 13
      XED_CATEGORY_COND_BR    = 14
      XED_CATEGORY_CONVERT    = 15
      XED_CATEGORY_DATAXFER   = 16
      XED_CATEGORY_DECIMAL    = 17
      XED_CATEGORY_FCMOV      = 18
      XED_CATEGORY_FLAGOP     = 19
      XED_CATEGORY_FMA4       = 20
      XED_CATEGORY_INTERRUPT  = 21
      XED_CATEGORY_IO         = 22
      XED_CATEGORY_IOSTRINGOP = 23
      XED_CATEGORY_LOGICAL    = 24
      XED_CATEGORY_LZCNT      = 25
      XED_CATEGORY_MISC       = 26
      XED_CATEGORY_MMX        = 27
      XED_CATEGORY_NOP        = 28
      XED_CATEGORY_PCLMULQDQ  = 29
      XED_CATEGORY_POP        = 30
      XED_CATEGORY_PREFETCH   = 31
      XED_CATEGORY_PUSH       = 32
      XED_CATEGORY_RDRAND     = 33
      XED_CATEGORY_RDSEED     = 34
      XED_CATEGORY_RDWRFSGS   = 35
      XED_CATEGORY_RET        = 36
      XED_CATEGORY_ROTATE     = 37
      XED_CATEGORY_SEGOP      = 38
      XED_CATEGORY_SEMAPHORE  = 39
      XED_CATEGORY_SHIFT      = 40
      XED_CATEGORY_SSE        = 41
      XED_CATEGORY_STRINGOP   = 42
      XED_CATEGORY_STTNI      = 43
      XED_CATEGORY_SYSCALL    = 44
      XED_CATEGORY_SYSRET     = 45
      XED_CATEGORY_SYSTEM     = 46
      XED_CATEGORY_TBM        = 47
      XED_CATEGORY_UNCOND_BR  = 48
      XED_CATEGORY_VFMA       = 49
      XED_CATEGORY_VTX        = 50
      XED_CATEGORY_WIDENOP    = 51
      XED_CATEGORY_X87_ALU    = 52
      XED_CATEGORY_XOP        = 53
      XED_CATEGORY_XSAVE      = 54
      XED_CATEGORY_XSAVEOPT   = 55
      TR_MUL                  = 56
      TR_DIV                  = 57
      TR_FMUL                 = 58
      TR_FDIV                 = 59
      TR_NOP                  = 60
      PREFETCH_NTA            = 61
      PREFETCH_T0             = 62
      PREFETCH_T1             = 63
      PREFETCH_T2             = 64
      GPU_EN                  = 65
      CPU_OPCODE_LAST         = 66
    end
  end

  class TraceInstruction < BitStruct
    unsigned :m_num_read_regs,    8, "Number Of Source Registers"
    unsigned :m_num_dest_regs,    8, "Number of Destination Registers"
    octets   :m_src,              72, "Source Register IDs"
    octets   :m_dst,              48, "Destination Register IDs"
    unsigned :m_cf_type,          8, "Branch Type"
    unsigned :m_has_immediate,    8, "Whether Has Immediate Field"
    unsigned :m_opcode,           8, "Opcode"
    unsigned :m_has_st,           8, "Whether Has Store Operation"
    unsigned :m_is_fp,            8, "Whether Is a Floating Point Operation"
    unsigned :m_write_flg,        8, "Write Flag"
    unsigned :m_num_ld,           8, "Number of Load Operations"
    unsigned :m_size,             8, "Instruction Size"
    unsigned :m_ld_vaddr1,        32, "Load Address 1"
    unsigned :m_ld_vaddr2,        32, "Load Address 2"
    unsigned :m_st_vaddr,         32, "Store Address"
    unsigned :m_instruction_addr, 32, "PC Address"
    unsigned :m_branch_target,    32, "Branch Target Address"
    unsigned :m_mem_read_size,    8, "Memory Read Size"
    unsigned :m_mem_write_size,   8, "Memory Write Size"
    unsigned :m_rep_dir,          8, "Repetition Direction"
    unsigned :m_actually_taken,   8, "Whether Branch Is Actually Taken"
  end

  def self.readInstructionMacsim(io)
    while (@buffer.length - @position) < (TraceInstruction.bit_length/8) && !io.eof?
      @buffer << @zlibReader.read(10000)
    end

    @buffer.pos = @position
    str = @buffer.read(TraceInstruction.bit_length / 8)
    if str.nil?
      return nil
    end
    @position += str.length

    instr = TraceInstruction.new(str)
    instr
  end

  def self.writeK6Instruction(instr)
    prefetch = false
    read     = false
    write    = false

    if instr.m_num_ld > 0
      if instr.m_opcode == Macsim::CPU_OPCODE::XED_CATEGORY_PREFETCH
        # Prefetch (Read)
        prefetch = true
      else
        # Load (Read)
        read = true
      end

      # Prefetch Instruction
      if instr.m_opcode == Macsim::CPU_OPCODE::XED_CATEGORY_PREFETCH ||
         (instr.m_opcode >= Macsim::CPU_OPCODE::PREFETCH_NTA &&
          instr.m_opcode <= Macsim::CPU_OPCODE::PREFETCH_T2)
        prefetch = true
      end

      va = instr.m_ld_vaddr1

      if prefetch
        puts "0x#{va.to_s(16)} P_FETCH #{@cycles}"
      else
        puts "0x#{va.to_s(16)} P_MEM_RD #{@cycles}"
      end
    end

    if instr.m_has_st > 0
      va = instr.m_st_vaddr
      puts "0x#{va.to_s(16)} P_MEM_WR #{@cycles}"
    end

    @cycles += 1
  end

  def self.eof?
    @zlibReader.eof? && @buffer.eof?
  end

  def self.openMacsim(io)
    @cycles = 0
    @buffer = StringIO.new
    @position = 0
    @buffer.pos = 0
    @zlibReader = Zlib::GzipReader.new(io)

    while !self.eof?
      instr = self.readInstructionMacsim(io)
      self.writeK6Instruction(instr)
    end

    @zlibReader.close
  end

  def self.detectMacsim(io)
    str = io.read(2)
    io.seek(-2, IO::SEEK_CUR)
    str.length == 2 && str[0].ord == 31 && str[1].ord == 139
  end

  def self.open(path_or_io)
    # Detect trace type

    io = path_or_io
    if io.is_a? String
      io = File.open(path_or_io, 'rb')
    end

    if self.detectMacsim(io)
      self.openMacsim(io)
    end

    io.close
  end
end

TraceConvert.open("trace.raw")
