#module "http"
public type Response
    status as long
end type
public function Fetch( ) as long
    return Send_( )
end function
function Send_( ) as long
    return 1
end function
