#!/usr/bin/ruby

# RUBYLIB=~/metasm strace -f ruby ./metabot.rb 2>&1 | grep write
# nux: export RUBYLIB=~/metasm

require 'metasm'
include Metasm

# stupid rip of https://github.com/jjyg/metabot/blob/master/metabot.rb

MAX_MESSAGE=440

# 
MEMSIZE=0x8000
UID=1002; EUID=UID
# 
CS64=0x33
SS64=0x2b

DS64=ES64=FS64=GS64=0
DS32=ES32=0x2b
GS32=0x63

class Metabot
	def initialize()
		start
	end
	
	def stop
		puts "[-] Shutting down."
		exit
	end

	def start
		while true
			begin
				print "imetasm> "
				input=gets.chomp
				if (input == 'exit' || input == 'quit')
					raise SystemExit
				end
				parse(input)
			rescue SystemExit, Interrupt
				stop
			rescue Exception
				puts "[-] loop #{$!}", $!.backtrace
			end
		end
	end


	def parse(message)
		return if not message

		command=message.match(/!(.+)/)

		if command
			command=command[1]
			cmd, arg=command.split(/\s+/, 2)
			cmd.downcase!

			case cmd
			when /^help$/
			answer="!a, !a16, !a32, !a64, !a.mips, !a.ppc, !a.arm or !a.sh4 shellcode to assemble. "\
				"!d, !d16, !d32, !d64 or !d.mips, !d.ppc, !d.arm or !d.sh4 shellcode to disassemble. "\
				"!c, !c16, !c32, !c64 or !c.mips, !c.ppc, !c.arm or !c.sh4  code c->shellcode. "\
				"!r, !r16, !r32 or !r64 asm to run assembly. "\
				"!fe float to encode float (single | double). "\
				"!fd float to decode float (single | double)."
			when /^a(|16|32|64|.mips|.arm|.ppc|.sh4)$/
				answer=assemble(arg, $1)
			when /^d(|16|32|64|.mips|.arm|.ppc|.sh4)$/
				answer=disassemble(arg, $1)
			when /^c(|16|32|64|.mips|.arm|.ppc|.sh4)$/
				answer=compile(arg, $1)
			when /^r(|16|32|64)$/
				answer=run_shellcode(arg, $1)
			when 'fe'
				answer=float_encode(arg)
			when 'fd'
				answer=float_decode(arg)
			else
				return
			end
			puts answer
		end
	end


	def float_encode(float)
		begin
			single=[float].pack('g').unpack("C*").map{|c| '%02x'%c}.join
			double=[float].pack('G').unpack("C*").map{|c| '%02x'%c}.join
			"0x#{single} | 0x#{double}"
		rescue
			$!
		end
	end


	def float_decode(float)
		begin
			single=[Integer(float)].pack("l").unpack("F")[0]
			double=[Integer(float)].pack("q").unpack("D")[0]
			single.to_s+" | "+double.to_s
		rescue
			$!
		end
	end

	def hexinspect(bin)
		hex=bin.unpack('C*').map{|c| '\\x%02x'%c}.join 
		asc=bin.split('').map{|b| (b=~ /([^[:print:]])/) ? "\\x%02x"%b.unpack('C').first : b}.join
		'"'+hex+'" | "'+asc+'"'
	end

	def assemble(shellcode, sz)

		quote=false
		shellcode=shellcode.split(';').map{|t|
			t.strip!
			if t.count("'")%2==1
				quote=quote ? false : true
			end
			t+(quote ? ';' : "\n")
		}.join
		return if shellcode.strip.empty?

		switched=""
		case sz
		when '16'
			bin=Shellcode.assemble(Ia32.new(16), shellcode).encode_string
		when '32'
			bin=Shellcode.assemble(Ia32.new, shellcode).encode_string
		when '64'
			bin=Shellcode.assemble(X64.new, shellcode).encode_string
		when '.mips'
			begin
				bin=Shellcode.assemble(MIPS.new, shellcode).encode_string
			rescue
				return $!
			end
		when '.arm'
			begin
				bin=Shellcode.assemble(ARM.new, shellcode).encode_string
			rescue
				return $!
			end
		when '.ppc'
			begin
				bin=Shellcode.assemble(PPC.new, shellcode).encode_string
			rescue
				return $!
			end
		when '.sh4'
			begin
				bin=Shellcode.assemble(Sh4.new, shellcode).encode_string
			rescue
				return $!
			end									
		else
			begin
				bin=Shellcode.assemble(Ia32.new, shellcode).encode_string
				switched=" (32 bits)"
			rescue
				bin=Shellcode.assemble(X64.new, shellcode).encode_string
				switched=" (64 bits)"
			end
		end
		hexinspect(bin) + switched
	rescue
		$!
	end


	def disassemble(shellcode, sz)
		shellcode.gsub!('"', '')
		shellcode.strip!
		return if shellcode.empty?
		shellcode.gsub!(/(\\x([0-9a-fA-F]{2}))/){|m| [$+].pack('H*')}

		shellcode=EncodedData.new(shellcode, :export=> { 'ep'=> 0 })

		case sz
		when '64'
			disass=Shellcode.disassemble(X64.new, shellcode)
		when '16'
			disass=Shellcode.disassemble(Ia32.new(16), shellcode)
		when '32'
			disass=Shellcode.disassemble(Ia32.new, shellcode)
		when '.mips'
			begin
				disass=Shellcode.disassemble(MIPS.new, shellcode)
			rescue
				return $!
			end
		when '.arm'
			begin
				disass=Shellcode.disassemble(ARM.new, shellcode)
			rescue
				return $!
			end
		when '.ppc'
			begin
				disass=Shellcode.disassemble(PPC.new, shellcode)
			rescue
				return $!
			end	
		when '.sh4'
			begin
				disass=Shellcode.disassemble(Sh4.new, shellcode)
			rescue
				return $!
			end												
		else
			disass=Shellcode.disassemble(Ia32.new, shellcode)
		end
		out=disass.instructionblocks.sort_by { |block| block.address }.map{|block|
			((l=disass.get_label_at(block.address)) ? "#{l}: " : '') +
				block.list.map{|instr|
				instr.instruction.to_s
			}.join(" ; ")
		}.join(" - ")

		out.sub!('ep: ', '') if out[4..-1] !~ /ep/

			out=='' ? 'No decoding found :(' : out
	rescue
		$!
	end


	def compile(c, sz)
		case sz
		when '64'
			bin=Shellcode.compile_c(X64.new, c).encode_string
		when '32'
			bin=Shellcode.compile_c(Ia32.new, c).encode_string
		when '16'
			bin=Shellcode.compile_c(Ia32.new(16), c).encode_string
		when '.mips'
			begin
				bin=Shellcode.compile_c(MIPS.new, c).encode_string
			rescue
				return $!
			end
		when '.arm'
			begin
				bin=Shellcode.compile_c(ARM.new, c).encode_string
			rescue
				return $!
			end
		when '.ppc'
			begin
				bin=Shellcode.compile_c(PPC.new, c).encode_string
			rescue
				return $!
			end
		when '.sh4'
			begin
				bin=Shellcode.compile_c(Sh4.new, c).encode_string
			rescue
				return $!
			end									
		else
			bin=Shellcode.compile_c(Ia32.new, c).encode_string
		end
		hexinspect(bin)
	rescue
		$!
	end


	def do_run_shellcode(shellcode, sz)
		begin
			dl=DynLdr

			allregs=%w[rax rbx rcx rdx rsi rdi rbp r8 r9 r10 r11 r12 r13 r14 r15]
			gpregs=%w[rax rbx rcx rdx rsi rdi rflags]
			# GPRs save area
			gprs="\0"*8*gpregs.length

			dl.new_api_c <<EOS
long mmap(long addr, long length, long prot, long flags, long fd, long offset);
long munmap(long addr, long length);

struct user_desc {
  unsigned __int32 entry_number;
  unsigned __int32 base_addr;
  unsigned __int32 limit;
  int seg_32bit:1;
  int contents:2;
  int read_exec_only:1;
  int limit_in_pages:1;
  int seg_not_present:1;
  int useable:1;
};

long modify_ldt(int func, struct user_desc*ptr, long bytecount);

#define PROT_R 1
#define PROT_W 2
#define PROT_X 4

#define MAP_PV 0x2
#define MAP_FIXED 0x10 
#define MAP_ANON 0x20
#define MAP_32 0x40
EOS
			if not dl.respond_to? :mmap
				puts "[-] mmap not found"
				return
			end

			if not dl.respond_to? :modify_ldt
				puts "[-] modify_ldt not found"
				return
			end		

			case sz
			when '32'
				# alloc memory in 32b user-space
				code32=dl.mmap(0, MEMSIZE, dl::PROT_R|dl::PROT_W|dl::PROT_X, dl::MAP_PV|dl::MAP_ANON|dl::MAP_32, -1, 0)
				if code32==-1
					puts "[-] mmap failed (code32)"
					return
				end
				# puts "[+] Allocated code32 at: #{code32.to_s(16)}"

				stack32=dl.mmap(0, MEMSIZE, dl::PROT_R|dl::PROT_W, dl::MAP_PV|dl::MAP_ANON|dl::MAP_32, -1, 0)
				if stack32==-1
					puts "[-] mmap failed (stack32)"
					return
				end
				# puts "[+] Allocated stack32 at: #{stack32.to_s(16)}"

				# Our LDT: 
				# 0 empty
				# 1 code32 segment
				# ...
				# create a LDT, map code segment to our memory and copy shellcode into
				# entry=1
				# ldt_entry base_addr size_in_pages
				# 32bits:1 type:2 (2=code) readonly:0 limit_in_pages:1 seg_not_present:0 usable:1
				# MODIFY_LDT_CONTENTS_CODE=2
				# http://lxr.linux.no/#linux+v2.6.37/arch/x86/include/asm/desc.h#L9
				# http://lxr.linux.no/#linux+v2.6.37/arch/x86/include/asm/desc_defs.h#L22
				# http://www.x86-64.org/pipermail/discuss/2007-May/009913.html
				# http://blog.oxff.net/2010/4/3/64bit_Linux%2C_MAP_32BIT_and_fs_Segment.html
				struct=dl.alloc_c_struct('user_desc')
				struct.entry_number=1
				struct.base_addr=0
				struct.limit=(1<<32)-1
				struct.seg_32bit=1
				struct.contents=2
				struct.read_exec_only=0
				struct.limit_in_pages=1
				struct.seg_not_present=0
				struct.useable=1
				#struct=[1, 0, 0xffffffff, 0b1_0_1_1_10_1].pack("VVVV")
				if dl.modify_ldt(1, struct, struct.sizeof)!=0
					puts "[-] modify_ldt failed"
					return 
				end

				# puts "[+] ldt entry created !"

				# init stack for code32
				dl.memory_write(stack32+MEMSIZE-12, [CS64].pack('V')) # 64b cs
				dl.memory_write(stack32+MEMSIZE-16, [(code32+shellcode.length+5+1)].pack('V')) # RIP to stager

				# ldt code segment selector. index: 1, table: 1, rpl: 3
				cs32=0xf

				stager=Shellcode_RWX.assemble(X86_64.new, <<EOS).encode_string			
db #{shellcode.inspect}
mov esp, #{stack32+MEMSIZE-16}
retf.i32
mov rsp, [rip-$_+1f]
jmp [rip-$_+2f]
1: dq 0xdeadbeefc0feb4be ; rsp, patch me !
2: dq 0xdeadbeefc0feb4be ; rip, patch me !
EOS
				dl.memory_write(code32, stager)

			when '16'
				code16=dl.mmap(0x4000, 0x2000, dl::PROT_R|dl::PROT_W|dl::PROT_X, dl::MAP_PV|dl::MAP_ANON|dl::MAP_FIXED, -1, 0)
				if code16==-1
					return
				end

				stack16=dl.mmap(0x8000, 0x2000, dl::PROT_R|dl::PROT_W, dl::MAP_PV|dl::MAP_ANON|dl::MAP_FIXED, -1, 0)
				if stack16==-1
					return
				end

				struct=dl.alloc_c_struct('user_desc')
				struct.entry_number=1
				struct.base_addr=0
				struct.limit=(1<<32)-1
				struct.seg_32bit=0
				struct.contents=2
				struct.read_exec_only=0
				struct.limit_in_pages=1
				struct.seg_not_present=0
				struct.useable=1
				if dl.modify_ldt(1, struct, struct.sizeof)!=0
					return 
				end

				# init stack for code32
				dl.memory_write(stack16+0x2000-14, [CS64].pack('v')) # 64b cs
				dl.memory_write(stack16+0x2000-16, [(code16+shellcode.length+3+1)].pack('v')) # RIP to stager

				# ldt code segment selector. index: 1, table: 1, rpl: 3
				cs32=0xf

				stager=Shellcode.assemble(X86_64.new, <<EOS).encode_string
db #{shellcode.inspect}
db 0xbc
dw #{stack16+0x2000-16}
retf.i32
mov rsp, [rip-$_+1f]
jmp [rip-$_+2f]
1: dq 0xdeadbeefc0feb4be ; rsp, patch me !
2: dq 0xdeadbeefc0feb4be ; rip, patch me !
EOS
				dl.memory_write(code16, stager)
			end

			dl.new_func_asm("int wrapper(void *);", <<EOS, selfmodifyingcode=true)
// pushad
#{allregs.map{|r| "push #{r}" }.join("\n")}
// rdi=arg0=ptr to save buffer
push rdi
; clean GPRs
#{allregs.map{|r| "xor #{r}, #{r}" }.join("\n")}
; invoke our shellcode !
call sc
; original rdi=arg0
pop r9
; save results
mov [r9+0*8], rax
mov [r9+1*8], rbx
mov [r9+2*8], rcx
mov [r9+3*8], rdx
mov [r9+4*8], rsi
mov [r9+5*8], rdi
; rflags
mov [r9+6*8], r15
; write grps to stdout
mov rdx, 7*8
mov rsi, r9
mov rdi, #{$stdout.fileno}
mov rax, 1
syscall
; exit 
mov edi, 37
mov rax, 60
syscall
hlt
; never executed ...
// popad 
#{allregs.reverse.map{|r| "pop #{r}"}.join("\n")}
// ret 0
xor rax, rax
ret
.align 16
sc:
#{	
case sz
when '64'
	<<STACK
	mov rax, rsp
	and rsp, ~(0x10-1)
	push rax
	xor rax, rax
	mov r14, rsp
	sub rsp, 0x1008
	push rax
	popfd
	db #{shellcode.inspect}
	mov rsp, r14
	pushfd
	pop r15
	; add rsp, 0x1008
	pop rsp
STACK
when '32'
	<<TRAMPOLINE
	mov rax, #{SS64}	; ss 
	push rax
	; alloc some stack
	mov rax, #{(stack32+MEMSIZE-16-0x2000) << 32}
	push rax		; eflags then esp
	mov rax, #{(cs32 << 32) | code32}
	push rax		; eip then cs
	lea rcx, [rsp+24]	; original rsp
	mov rax, #{code32+stager.length-16}
	mov [rax], rcx
	lea rcx, [rip-$_+back]
	mov rax, #{code32+stager.length-8}
	mov [rax], rcx
	xor rcx, rcx
	mov rax, #{DS32}
	mov ds, rax
	mov rax, #{ES32}
	mov es, rax	
	xor rax, rax
	iret.i32
	back:
	nop
	mov r10, #{DS64}
	mov ds, r10
	mov r10, #{ES64}
	mov es, r10
	pushfd
	pop r15	
TRAMPOLINE
when '16'
	<<TRAMPOLINE
	mov rax, #{SS64}	; ss 
	push rax
	; alloc some stack
	mov rax, #{(stack16+0x2000-16-0x100) << 32}
	push rax		; eflags then esp
	mov rax, #{(cs32 << 32) | code16}
	push rax		; eip then cs
	lea rcx, [rsp+24]	; original rsp
	mov rax, #{code16+stager.length-16}
	mov [rax], rcx
	lea rcx, [rip-$_+back]
	mov rax, #{code16+stager.length-8}
	mov [rax], rcx
	xor rcx, rcx
	mov rax, #{DS32}
	mov ds, rax
	mov rax, #{ES32}
	mov es, rax	
	xor rax, rax
	iret.i32
	back:
	nop
	mov r10, #{DS64}
	mov ds, r10
	mov r10, #{ES64}
	mov es, r10
	pushfd
	pop r15	
TRAMPOLINE
end
}
ret
EOS
			# enter SECCOMP mode bro
			dl.new_api_c("int prctl(int option, long, long, long, long);", "/lib/libc.so.6")
			if not dl.respond_to? :prctl	
				puts "[-] prctl not found"
				return
			end

			PTrace.traceme

			status=dl.prctl(22, 1, 0, 0, 0)
			if status!=0
				puts "[-] prctl call failed"
				return
			end	

			status=dl.wrapper(gprs)
			if status!=0
				# puts "[-] shellcode failed"
				return
			end

		rescue
			puts "[-] do_run_shellcode: #{$!}"
		ensure
			case sz
			when '16'
				dl.memory_free(code16)
				dl.memory_free(stack16)
			when '32'
				dl.memory_free(code32)
				dl.memory_free(stack32)
			end
		end
	end



	def run_shellcode(shellcode, sz)
		shellcode.strip!
		return if shellcode.empty?

		quote=false
		shellcode=shellcode.split(';').map{|t|
			t.strip!
			if t.count("'")%2==1
				quote=quote ? false : true
			end
			t+(quote ? ';' : "\n")
		}.join.strip
		return if shellcode.empty?

		begin
			case sz
			when '32'
				cpu=Ia32.new
				raw=Shellcode.assemble(cpu, shellcode).encode_string
			when '64'
				cpu=X64.new
				raw=Shellcode.assemble(cpu, shellcode).encode_string
			when '16'
				cpu=Ia32.new(16)
				raw=Shellcode.assemble(cpu, shellcode).encode_string
			else
				begin
					cpu=Ia32.new
					raw=Shellcode.assemble(cpu, shellcode).encode_string
					sz='32'
				rescue
					cpu=X64.new
					raw=Shellcode.assemble(cpu, shellcode).encode_string
					sz='64'
				end
			end
		rescue
			return $!
		end

		dl=DynLdr
		dl.new_api_c <<EOS
int close(int fd);
#define PTRACE_GETSIGINFO 0x4202
long ptrace(int request, int pid, void *addr, void *data);
EOS

		if not dl.respond_to? :close	
			puts "[-] close not found"
			return
		end

		# shellcode can be compiled, now create a subprocess and run it into its context
		#Signal.trap('CHLD', 'IGNORE')
		Signal.trap('PIPE', 'IGNORE')
		begin
			# pipe
			rd, wr=IO.pipe

			#puts "rd: #{rd.fileno} | wr: #{wr.fileno}"
			pid=Process.fork{
				begin
					# 2s max CPU time
					# RLIMIT_CPU
					Process.setrlimit(0, 2)
					# max memory : 120 mb
					# RLIMIT_AS
					Process.setrlimit(9, 120*1024*1024)

					# close all fds remaining. Not the one for our pipe
					# getrlimit RLIMIT_NOFILE, returns : a value one greater than the maximum file descriptor number that can be opened by this process.
					maxfd=Process.getrlimit(7)[1]-1
					dl.new_func_c <<EOS
int close(int);			
void closefds(int max, int keep)
{
	int fd;
	for(fd=0; fd<=max; fd++)
	{
		if(keep!=fd)
			close(fd);
	}
}
EOS
					dl.closefds(maxfd, wr.fileno)

					# stdout assigned to our pipe
					$stdout=wr

					# try running shellcode
					do_run_shellcode(raw, sz)

					exit!(0)
				end
			}
			#puts "[+] Forked #{pid}"
			# Process.waitpid(pid)
			wr.close

			err="Something wrong happened !"
			fuck=false
			exitcode=0
			trace=PTrace.new(pid, false)
			while ::Process.waitpid(pid)
				status=$?
				#puts status.inspect

				if status.exited?
					exitstatus=status.exitstatus
					break
				end

				if status.signaled?
					break
				end

				if status.stopped?
					# puts status.stopsig
					rip=trace.peekusr(trace.reg_off['RIP'])
					instr=trace.readmem(rip, 16) rescue ''
					di=Shellcode.disassemble(cpu, instr).instructionblocks[0].list[0].instruction rescue nil
					di ||=hexinspect(instr)

					regs=%w[RAX RBX RCX RDX RSI RDI RSP RIP].map{|reg|
						"#{reg.capitalize}: 0x%X" % trace.peekusr(trace.reg_off[reg])
					}.join(" | ")

					case sz
						when '32'
							regs.gsub!('R', 'E')
						when '16'
							regs.gsub!('R', '')
					end

					# siginfo="\0"*128
					# dl.ptrace(dl::PTRACE_GETSIGINFO, pid, 0, siginfo)
					# puts trace.getsiginfo.si_code
					# cr2=siginfo.unpack("Q*")[2]
=begin
/* `si_code' values for SIGSEGV signal.  */
enum
{
SEGV_MAPERR = 1,              /* Address not mapped to object.  */
# define SEGV_MAPERR    SEGV_MAPERR
SEGV_ACCERR                   /* Invalid permissions for mapped object.  */
# define SEGV_ACCERR    SEGV_ACCERR
};					
=end
					case status.stopsig
						when ::Signal.list["SEGV"]
							regs<<" | #{if trace.getsiginfo.si_code==2 then 'Write' else 'Read' end}: 0x%X" % trace.getsiginfo._sigfault.si_addr							
							err="Broken: #{di} | #{regs}"
							trace.kill
							fuck=true
							next

						when ::Signal.list["TRAP"]
							# icebp
							puts instr
							if instr[0]=0xf1
								trace.kill

							# trap flag	
							else
								# disable trap flag
								rflags=trace.peekusr(trace.reg_off['RFLAGS'])
								rflags&=~0x100
								trace.pokeusr(trace.reg_off['RFLAGS'], rflags)
							end

							fuck=true
							err="It's a trap: #{di} | #{regs}"

							if instr[0]=0xf1
								next
							end

						when ::Signal.list["ILL"]
							err="Illegal instruction: #{di} | #{regs}"
							trace.kill
							fuck=true
							next

						else
							trace.kill
							fuck=true
							next
						end
				end

				trace.cont
			end

			result=rd.read
			rd.close

			if fuck or result.length==0 
				return err	
			elsif result.length==7*8 and exitstatus==37
				# dump regs	
				rax, rbx, rcx, rdx, rsi, rdi, rflags=result.unpack('Q*')

				flags=[[0, "CF"], [2, "PF"], [4, "AF"], [6, "ZF"], [7, "SF"], [8, "TF"], [10, "DF"], [11, "OF"]].map{|bit, flag|
					flag if (rflags>>bit)&1!=0
				}.join(" ")

				out="Rax: 0x%X | Rbx: 0x%X | Rcx: 0x%X | Rdx: 0x%X | Rsi: 0x%X | Rdi: 0x%X | RFlags: 0x%X #{flags}" % [rax, rbx, rcx, rdx, rsi, rdi, rflags]
				case sz
					when '32'
						out.gsub!('R', 'E')
					when '16'
						out.gsub!('R', '')
				end
				return out
			else
				return result		
			end
		rescue
			puts "[-] run_shellcode: #{$!}"
			return "Something wrong happened ! #{$!}"
		end
	end
end

if $0==__FILE__
	Metabot.new()
end


