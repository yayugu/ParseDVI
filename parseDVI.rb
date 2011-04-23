# coding: UTF-8
require 'bigdecimal'
require 'pp'

@jis_pre = [27, 36, 66].pack("C*")
@jis_post = [27, 40, 66].pack("C*")
def parseJIS(str)
  (@jis_pre + str + @jis_post)
    .encode('utf-8', 'iso-2022-jp')
end

def parseUInt(str)
  str.unpack("C*")[0]
end

def parseInt(str)
  str.unpack("c*")[0]
end

def readInt(fp, byte, signed = false)
  data = fp.read(byte).unpack("C*")  
  num = case byte
  when 1
    data[0]
  when 2
    (data[0] << 8) + data[1]
  when 3
    (data[0] << 16) + (data[1] << 8) + data[2]
  when 4
    (data[0] << 24) + (data[1] << 16) + (data[2] << 8) + data[3]
  end

  msb = num >> (byte * 8 - 1)
  if signed and msb == 1
    num = -((~num + 1) & [0xff, 0xffff, 0xffffff, 0xffffffff][byte - 1])
  end
  
  num
end

class Integer
  def to_pt
    @memo ||= {}
    @memo[self] ||= (BigDecimal.new("2").power(-16) * self).to_s("F")
  end
end

# 連続したset, putをつなげる
def join_op(s)
  new_s = []
  new_s_idx = -1
  old = nil
  s.each_with_index do |op, i|
    name = op[:name]
    if name == :set or name == :put
      if name == old
        new_s[new_s_idx][:str] += op[:str]
      else
        new_s << op
        new_s_idx += 1
      end
      old = name
    else
      old = nil
      new_s << op
      new_s_idx += 1
    end
  end
  new_s
end



s = []
b = open(ARGV[0], 'rb')

unless b.respond_to?(:readbyte)
  def b.readbyte
    self.read(1).unpack("C*")[0]
  end
end


while c = b.read(1)
  c = parseUInt(c)
  case c
  when 0..127
    s << {name: :set, str: sprintf("%c", c)}
  when 128
    s << {name: :set, str: b.read(1)}
  when 129
    s << {name: :set, str: parseJIS(b.read(2))}
  when 130
    #s << "set3 "; b.read(3)
  when 131
    #s << "set4 "; b.read(4)
  when 132
    s << {name: :set_rule}; b.read(8)
  when 133
    s << {name: :put, str: b.read(1)}
  when 134
    s << {name: :put, str: parseJIS(b.read(2))}
  when 135
    #s << "put3 "; b.read(3)
  when 136
    #s << "put4 "; b.read(4)
  when 137
    s << {name: :put_rule}; b.read(8)
  when 128
    #s << "nop"
  when 139
    s << {name: :bop}
    10.times{|i| b.read(4)}
    b.read(4)
  when 140
    s << {name: :eop}
  when 141
    s << {name: :push}
  when 142
    s << {name: :pop}
  when 143..146
    s << {name: :right, b: readInt(b, c - 142, true)}
  when 147
    s << {name: :w0}
  when 148..151
    s << {name: :w, b: readInt(b, c - 147, true)}
  when 152
    s << {name: :x0}
  when 153..156
    s << {name: :x, b: readInt(b, c - 152, true)}
  when 157..160
    s << {name: :down, b: readInt(b, c - 156, true)}
  when 161
    s << {name: :y0}
  when 162..165
    s << {name: :y, b: readInt(b, c - 161, true)}
  when 166
    s << {name: :z0}
  when 167..170
    s << {name: :z, b: readInt(b, c - 166, true)}
  when 171..234
    s << {name: :fnt, k: c - 171}
  when 235..238
    s << {name: :fnt, k: parseUInt(b.read(c - 234))}
  when 239..242
    s << {name: :xxx,
          k: k = readInt(b, c - 238),
          x: b.read(k)}
  when 243..246
    s << {name: :fnt_def,
          k: parseUInt(b.read(c - 242)),
          c: parseUInt(b.read(4)),
          s: readInt(b, 4, true),
          #s: p(b.read(4)),
          d: readInt(b, 4, true),
          a: a = b.readbyte,
          l: l = b.readbyte,
          n: b.read(a + l)}
  when 247
    s << {name: :pre,
          i: b.read(1),
          num: b.read(4),
          den: b.read(4),
          mag: readInt(b, 4)}
    "  " + b.read(b.readbyte)
  when 248
    s << {name: :post}
    b.read(28)
  when 249
    s << {name: :post_post}
    break
  when 250..254
    s << {name: :undefined}
  when 255
    s << {name: :dir, dir: (b.readbyte == 0 ? "yoko" : "tate")}
  end
end

s = join_op(s)

Register = Struct.new('Register', :h, :v, :w, :x, :y, :z)
out = ''
stack = [Register.new(0, 0, 0, 0, 0, 0)]
fnt_nums = {}
page = 0
s.each do |op|
  case op[:name]
  when :push
    stack.push stack.last.dup
  when :pop
    stack.pop
  else
    out << "    " * (stack.length - 1) << op[:name].to_s
    case op[:name]
    when :set, :put
      out << " " << op[:str]
    when :bop
      stack[-1] = Register.new(0, 0, 0, 0, 0, 0)
      page += 1
      out << " [#{page}]"
    when :fnt_def
      fnt_nums[op[:k]] = op
      out << " " << op[:n] << " " << op[:s].to_pt
    when :fnt
      op = fnt_nums[op[:k]]
      out << " " << op[:n] << " " << op[:s].to_pt    
    when :w0
      out << " " << stack.last.w.to_pt
    when :w
      stack.last.w = op[:b]
      out << " " << op[:b].to_pt
    when :x0
      out << " " << stack.last.x.to_pt
    when :x
      stack.last.x = op[:b]
      out << " " << op[:b].to_pt
    when :y0
      out << " " << stack.last.y.to_pt
    when :y
      stack.last.y = op[:b]
      out << " " << op[:b].to_pt
    when :z0
      out << " " << stack.last.z.to_pt
    when :z
      stack.last.z = op[:b]
      out << " " << op[:b].to_pt
    when :right
      out << " " << op[:b].to_pt
    when :down
      out << " " << op[:b].to_pt
    when :xxx
      out << " " << op[:x]
    when :pre
      out << " mag=" << op[:mag].to_s
    when :dir
      out << " " << op[:dir]
    end
    out << "\n"
  end
end

print out
