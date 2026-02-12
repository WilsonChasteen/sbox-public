HEADER
{
	Description = "Dazzle GI - Surfel Dispatch Fixup";
	DevShader = true;
}

MODES
{
	Default();
}

CS
{
	RWByteAddressBuffer DispatchBuffer < Attribute( "DispatchBuffer" ); >;
	ByteAddressBuffer CountBuffer < Attribute( "CountBuffer" ); >;

	[numthreads( 1, 1, 1 )]
	void MainCs()
	{
		uint count = CountBuffer.Load( 0 );
		uint groups = ( count + 63 ) / 64;
		DispatchBuffer.Store( 0, groups );
		DispatchBuffer.Store( 4, 1 );
		DispatchBuffer.Store( 8, 1 );
	}
}
