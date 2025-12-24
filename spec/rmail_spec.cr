require "./spec_helper"
require "../src/rmail/quoted_printable.cr"

describe RMail::QuotedPrintable do
  it "encodes and decodes a quotable-printable text" do
    data = <<-HTM
<html lang=\"ja\">\r
<head>\r
  <title>日本語タイトル</title>\r
</head>\r
<body>\r
  <h1>見出し</h1>\r
  <p>本文<p>\r
</body>\r
</html>\r
HTM
    encoded = RMail::QuotedPrintable.encode(data)
    expected = <<-HTM
<html lang=3D"ja">\r
<head>\r
  <title>=E6=97=A5=E6=9C=AC=E8=AA=9E=E3=82=BF=E3=82=A4=E3=83=88=E3=83=AB</t=\r
itle>\r
</head>\r
<body>\r
  <h1>=E8=A6=8B=E5=87=BA=E3=81=97</h1>\r
  <p>=E6=9C=AC=E6=96=87<p>\r
</body>\r
</html>=0D
HTM
    encoded.should eq(expected)

    decoded = RMail::QuotedPrintable.decode_string(encoded)
    decoded.should eq(data)
  end
end

