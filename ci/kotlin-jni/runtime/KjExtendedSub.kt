package rt.kj

// Hand-written subclasses of the +j records, to prove that both base classes are open.

class KjExtendedSub(value: Int, name: String) : KjExtendedBase(value, name)
class KjEmptyExtendedSub : KjEmptyExtendedBase()
