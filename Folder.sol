//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Ijoe} from './interfaces/ijoe.sol';
import {Ijoetroller} from './interfaces/joetroller.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "hardhat/console.sol";


contract Folder {
    
    using SafeMath for uint256;

    address owner;
    IERC20 token;
    Ijoe pool;
    Ijoetroller joetroller;
    uint256 supplied = 0;
    uint256 borrowed = 0;
    uint256 collateralFactor;
    uint256 fifteen = 1000000000000000;
    uint256 eighteen = 1000000000000000000;

    event Folded(
        uint256 _supplied,
        uint256 _borrowed
    );

    event Unfolded (
        uint256 amount
    );

    constructor() {
        owner = msg.sender;
    }

    function decimal(uint256 _number) internal view returns (uint256){
        return _number.div(fifteen);
    }

    function _lend(uint256 _amount) internal {
        pool.mint(_amount);
        console.log('lent', _amount);

    }

    function _borrow(uint256 _amount) internal {
        pool.borrow(_amount);
        console.log('borrowed', _amount);
    }

    function _repay(uint256 _amount) internal {
        pool.repayBorrow(_amount);
        console.log('repayed', _amount);
    }

    function _redeem(uint256 _amount) internal returns (uint256) {

        return pool.redeemUnderlying(_amount);
    }

    function _enterMarket(address _pool) internal {
        // Enter the market so you can borrow another type of asset
        address[] memory jtokens = new address[](1);
        jtokens[0] = _pool;
        uint256[] memory errors = joetroller.enterMarkets(jtokens);
        if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
        }
    }

    function checkLiquidity() internal view returns (uint256) {
        //Get my account's total liquidity value in Compound
        (uint256 error2, uint256 liquidity, uint256 shortfall) = joetroller.getAccountLiquidity(address(this));
        if (error2 != 0) {
            revert("Comptroller.getAccountLiquidity failed.");
        }
        require(shortfall == 0, "account underwater");
        require(liquidity > 0, "account has excess collateral");

        liquidity = liquidity.mul(90).div(100);

        console.log('Comp liquidity', liquidity);

        return liquidity;
    }

    function _checkLiquidity(uint _supplied, uint _borrowed) internal view returns (uint256) {
        
        uint256 total = _supplied.mul(collateralFactor).div(eighteen);

        uint256 liquidity = total.sub(_borrowed);

        console.log('liquidity', liquidity);

        return liquidity;
    }

    function _checkBalances() internal returns(uint256, uint256) {
        return (pool.balanceOfUnderlying(address(this)), pool.borrowBalanceCurrent(address(this)));
 
    }

    function _setCollateralFactor(address _pool) internal returns (bool) {
        (bool isListed, uint256 collateralFactorMantissa ) = joetroller.markets(_pool);
        console.log('collateral factor matissa', collateralFactorMantissa); 

        collateralFactor = collateralFactorMantissa;
        console.log('collateral factor', collateralFactor);

        return true;
    }

    function _checkMaxWithdrawable() internal returns (uint256) {
        (supplied, borrowed) = _checkBalances();
        //
        //uint256 liquidity = _checkLiquidity(supplied, borrowed);
        //console.log('liquidity', decimal(liquidity));
        uint256 needed = borrowed.mul(eighteen).div(collateralFactor); 
        console.log('needed for current borrow', decimal(needed));
        uint256 max = supplied.sub(needed);
        console.log('max to withdraw now', decimal(max));

        return max;
    }

    function fold(
        address _pool, 
        address _token,
        address _joetroller, 
        uint256 _amount,
        uint256 _rounds
        ) external returns (bool) {

        require(_amount > 0, "amount must be more than 0");
        
        //instantiate each address
        pool = Ijoe(_pool);
        token = IERC20(_token);
        joetroller = Ijoetroller(_joetroller);

        console.log('Dai addres', _token);

        token.transferFrom(msg.sender, address(this), _amount);
        console.log('transferred Dai in', decimal(_amount));
        
        token.approve(_pool, _amount.mul(10));

        console.log('approved Dai');    

        uint256 foldSupplied = 0;
        uint256 foldBorrowed = 0;

        //lend out deposited funds
        _lend(_amount);

        foldSupplied = foldSupplied.add(_amount);
        //allow deposit to be borrowed off of
        _enterMarket(_pool);
        console.log('market entered');

        //_setCollateralFactor(_pool);

        for(uint256 i=0; i < _rounds; i ++){

            //find out max borrow limit
            //uint256 borrow = _checkLiquidity(foldSupplied, foldBorrowed);
            uint256 compBorrow = checkLiquidity();
            console.log('amount to borrow', decimal(compBorrow));

            //Borrow 90% of max to avoid liquidations
            
            _borrow(compBorrow); 
            foldBorrowed = foldBorrowed.add(compBorrow);
            //lend it back in to protocol
            _lend(compBorrow);
            foldSupplied = foldSupplied.add(compBorrow);
        }

        //check balances
        //(uint256 tokens, uint256 jtokens ) = _checkBalances();

        emit Folded(foldSupplied, foldBorrowed);
        supplied = supplied.add(foldSupplied);
        borrowed = borrowed.add(foldBorrowed);

        console.log('supplied', foldSupplied, 'borrowed', foldBorrowed);

        return true;
    }

    function unfold(address _pool, address _token, address _joetroller, uint256 _amount) external returns (uint) {
        require(_amount > 0, "amount must be more than 0");
        
        pool = Ijoe(_pool);
        token = IERC20(_token);
        joetroller = Ijoetroller(_joetroller);

        _setCollateralFactor(_pool);

        uint256 max = _checkMaxWithdrawable();
        console.log('checked max', max);
        //
        token.approve(_pool, _amount.mul(10));

        while(max < _amount) {
            console.log('max is less than amount');
            uint256 redeem;
            if(max > borrowed){ 
                redeem = borrowed;
                console.log('max is larger than borrowed');
            } else{
                redeem = max.mul(90).div(100);
            }

            uint256 isRedeemed = _redeem(redeem);
            console.log('redeemed', isRedeemed);
            if(isRedeemed == 0 ){
                _repay(redeem);
            } else {
                return isRedeemed;
            }
            console.log('redoing max withdrawal');
            max = _checkMaxWithdrawable();
        }
        console.log('max greater than withdrawal');
        uint256 redeemed = _redeem(_amount);
        if(redeemed == 0) {
            token.transfer(msg.sender, _amount);

            emit Unfolded(_amount);
            return redeemed;
            } else {
                return redeemed;
            }

    }


    // Need this to receive ETH when `borrowEthExample` executes
    receive() external payable {}   

}
