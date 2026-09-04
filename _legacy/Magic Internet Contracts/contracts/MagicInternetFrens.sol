// SPDX-License-Identifier: MIT
/*
  

███╗░░░███╗██╗███████╗██████╗░███████╗███╗░░██╗░██████╗
████╗░████║██║██╔════╝██╔══██╗██╔════╝████╗░██║██╔════╝
██╔████╔██║██║█████╗░░██████╔╝█████╗░░██╔██╗██║╚█████╗░
██║╚██╔╝██║██║██╔══╝░░██╔══██╗██╔══╝░░██║╚████║░╚═══██╗
██║░╚═╝░██║██║██║░░░░░██║░░██║███████╗██║░╚███║██████╔╝
╚═╝░░░░░╚═╝╚═╝╚═╝░░░░░╚═╝░░╚═╝╚══════╝╚═╝░░╚══╝╚═════╝░


                               ▄▄▄▄,_
                           _▄████▀└████▄,
                       ▄███████▌   _▄█████▄_
                      ╓████████▄██▄╟██████████▄
                     ╓█████▀▀█████████████⌐ ╓████▄_
                     ╟███`     ╟███████████████████
                      ██▌     ▐████╙▀▐████████▀╙"╙▀" ,▄▄,
                     ,█▀       ,██▄▄ ▄▄█████w     ╒████████▄▄▄▄▄▄▄▄▄,,__
                              ª▀▀▀▀▀▀▀▀"" _,▄▄_▄▄█████████████████████▀▀
                            ╒██▄▄▄▄▄▄███████████████████████████▀▀╙"
                            ▐███████████████████▀▀▀▀▀╙╙"─
                         ▄██████████▀▀▀╙"`
                     ,▄███████▀""
                  ▄███████▀"                               _▄▄█▀▀████▄▄_
              ,▄████████▀                _,▄▄▄,_        ,███▀╓█▄   ╙█████▄
            ▄████████▀"             _▄█▀▀""╙▀██████▄ ╓█████▌ ╙▀"███L╙█████▌
             """╙"─               ▄███▐██▌╓██▄╙████████████▌ ╚█_`▀▀  ████▀
                              _▄█████" └█▄╙██▀ ╫████████████┐  ╙    '"─
                            '▀███████▌  "█─    ▐▀▀"  └"╙▀▀▀╙"         ▄▄_
                                 ╙▀▀██▌                           ,▄█████
                         ,▄▄▄▄▄▄▄▄,______              ___,▄▄▄█████████▀"
                        ██████████████████████████████████████████████▄
                        ╙██████████████████████████████████████████████
                            '╙▀▀█████████████████████████████████▀▀▀╙─
                                     `""╙"╙╙""╙╙╙╙""╙╙"""─`
 
█▀▄▀█ ▄▀█ █▀▀ █ █▀▀   █ █▄░█ ▀█▀ █▀▀ █▀█ █▄░█ █▀▀ ▀█▀   █▀▀ █▀█ █▀▀ █▄░█ █▀
█░▀░█ █▀█ █▄█ █ █▄▄   █ █░▀█ ░█░ ██▄ █▀▄ █░▀█ ██▄ ░█░   █▀░ █▀▄ ██▄ █░▀█ ▄█

https://www.mifrens.tech
https://twitter.com/miFrensTech
*/
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";



interface IFrenURI {
    function tokenURI(uint256 id) external view returns (string memory);
}

contract MagicInternetFrens is ERC721 {

    IFrenURI public frenURI;
    
    mapping(uint256 => uint256) public levels;
    mapping(uint256 => string) public levelURI;
    mapping(address => bool) public isAuth;
    mapping(uint256 => uint256) public miXP; //magic Internet Experience Points
    uint256 public _tokenIdCounter = 0; 
    uint256 public maxSupply = 3333; 
    address public owner;
 

   

    constructor() ERC721("Magic Internet Frens", "miFrens") {
         owner = msg.sender;
    }
  // Modifier to restrict access to owner only
    modifier onlyAuth() {
        require(msg.sender == owner || isAuth[msg.sender], "Caller is not the authorized");
        _;
    }
    function setIsAuth(address fren,bool isAuthorized) external onlyAuth{
        isAuth[fren]=isAuthorized;
    }



   function mint(address fren) public onlyAuth returns(uint256) {
    
    require(maxSupply>_tokenIdCounter,"Max Mint Reached");
     uint256 newTokenId = _tokenIdCounter; 

   
        _mint(fren, newTokenId);
        levels[newTokenId] = 0; // Start at level 0
        return newTokenId;
    }
    function SummonDedFren(address fren,uint256 _tokenId) public onlyAuth returns(uint256) {
    
        _mint(fren, _tokenId);
        levels[_tokenId] = 0; // Start at level 0
        return _tokenId;
    }


    function setmiXP(uint256 tokenId,uint256 _miXP) public onlyAuth {
       
        miXP[tokenId]=_miXP;
    }

    function levelUp(uint256 tokenId) public onlyAuth {
       
        levels[tokenId]++;
    }
    function levelDown(uint256 tokenId) public onlyAuth {
       
        levels[tokenId]--;
    }
    function setLevel(uint256 tokenId,uint256 level) public onlyAuth {
       
        levels[tokenId]=level;
    }
    function setLevelURI(uint256 level, string memory svgString) public onlyAuth {
        levelURI[level] = svgString;
    }

    function getURIForLevel(uint256 level) public view returns (string memory) {
        return levelURI[level];
    }

    function getmiXP(uint256 tokenId) public view returns (uint256) {
        return miXP[tokenId];
    }
    function getLevels(uint256 tokenId) public view returns (uint256) {
        return levels[tokenId];
    }
    function getTokenId() public view returns (uint256) {
        return _tokenIdCounter;
    }



 function tokenURI(uint256 id) public view override returns (string memory) {
        return frenURI.tokenURI(id);
    }

    function burnFren(uint256 id) external {
        require(isAuth[msg.sender], "Unauthorized");

        _burn(id);
    }

    // Helper function to convert uint256 to string
    function toString(uint256 value) internal pure returns (string memory) {
        // Convert a uint256 to a string
        // Implementation omitted for brevity
    }




    

function setFrenUri(IFrenURI _renderer) external onlyAuth {
        frenURI = _renderer;
    }

   
}
