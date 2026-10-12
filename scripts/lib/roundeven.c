// Round half to even, for the llvm.roundeven intrinsics. Bambu lowers them to calls of roundevenf
// and roundeven, which its C library does not have, so the definitions are linked into the IR.

float roundevenf(float x) {
  const float big = 8388608.0f; // 2^23: from here on every float is an integer
  float a = x < 0 ? -x : x;
  if (!(a < big))
    return x; // integer, infinity or NaN
  float r = (a + big) - big; // the addition rounds to nearest even
  return x < 0 ? -r : r;
}

double roundeven(double x) {
  const double big = 4503599627370496.0; // 2^52
  double a = x < 0 ? -x : x;
  if (!(a < big))
    return x;
  double r = (a + big) - big;
  return x < 0 ? -r : r;
}
