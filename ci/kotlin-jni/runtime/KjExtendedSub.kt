// Hand-written subclasses of the +j records, to prove that both _base classes are open.

class KjExtendedSub(value: Int, name: String) : KjExtended_base(value, name)
class KjEmptyExtendedSub : KjEmptyExtended_base()
