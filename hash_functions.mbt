///|
fn hash_function(name : String) -> Bool {
  match name {
    "MD5" | "SHA1" | "SHA256" | "SHA384" | "SHA512" => true
    _ => false
  }
}

///|
fn evaluate_hash(
  name : String,
  arg : Term,
  budget : Budget,
) -> Term raise QueryError {
  let text = simple_string(arg)
  budget.tick(n=text.length())
  let bytes = @utf8.encode(text)
  budget.tick(n=bytes.length())
  let digest = match name {
    "MD5" => @md5.hash(bytes[:])
    "SHA1" => @sha1.hash(bytes[:])
    "SHA256" => @sha2.hash(bytes[:])
    "SHA384" => @sha2.hash(bytes[:], kind=Sha384)
    "SHA512" => @sha2.hash(bytes[:], kind=Sha512)
    _ => raise Evaluation("unknown hash function")
  }
  let alphabet = "0123456789abcdef".to_array()
  let hex = StringBuilder()
  for byte in digest {
    let value = byte.to_int()
    hex.write_char(alphabet[value >> 4])
    hex.write_char(alphabet[value & 15])
  }
  literal(hex.to_string())
}
